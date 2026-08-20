defmodule Spectre.Prism.Adapter.ReqLLM do
  @moduledoc """
  Bridge for building Prism adapters on top of `ReqLLM` providers.

  The bundled Anthropic, DeepSeek, Groq, xAI, Mistral, and Cerebras adapters
  use this module. Applications can cover any additional ReqLLM provider with
  a small adapter module:

      defmodule MyApp.VeniceAdapter do
        use Spectre.Prism.Adapter.ReqLLM,
          provider: :venice,
          api_key_env: "VENICE_API_KEY",
          profiles: [
            fast: [model: "fast-model", rank: 10],
            balanced: [model: "balanced-model", rank: 20],
            deep: [model: "deep-model", rank: 30]
          ]
      end

  Provider credentials are resolved only at call time. A custom `base_url:`,
  `provider_options:`, and every ordinary ReqLLM generation option may be
  supplied through the Prism provider declaration.
  """

  alias Spectre.Inference.Response, as: SpectreResponse
  alias Spectre.Prism.Adapter.Client
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.Prompt

  @generation_control_options [
    :api_key_env,
    :base_url,
    :dimensions,
    :embedding_model,
    :encoder_model,
    :model,
    :model_extra,
    :req_llm_module,
    :req_llm_provider
  ]

  @embedding_control_options [
    :api_key_env,
    :base_url,
    :embedding_model,
    :encoder_model,
    :model,
    :model_extra,
    :req_llm_module,
    :req_llm_provider
  ]

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)
    profiles = Keyword.fetch!(opts, :profiles)
    classifier = Keyword.get(opts, :classifier, :fast)
    embedding = Keyword.get(opts, :embedding)
    api_key_env = Keyword.get(opts, :api_key_env)

    options =
      [req_llm_provider: provider]
      |> maybe_keyword_put(:api_key_env, api_key_env)
      |> Keyword.merge(Keyword.get(opts, :options, []))

    quote bind_quoted: [
            provider: provider,
            profiles: profiles,
            classifier: classifier,
            embedding: embedding,
            options: options
          ] do
      @behaviour Spectre.Prism.Adapter
      @behaviour Spectre.LLM

      @prism_req_llm_provider provider
      @prism_req_llm_profiles profiles
      @prism_req_llm_classifier classifier
      @prism_req_llm_embedding embedding
      @prism_req_llm_options options

      @impl Spectre.Prism.Adapter
      def catalog do
        %{
          options: @prism_req_llm_options,
          profiles: @prism_req_llm_profiles,
          classifier: @prism_req_llm_classifier,
          embedding: @prism_req_llm_embedding
        }
      end

      @impl Spectre.LLM
      def complete(prompt, opts \\ []) do
        Spectre.Prism.Adapter.ReqLLM.complete(@prism_req_llm_provider, prompt, opts)
      end

      @impl Spectre.LLM
      def complete_plan(plan, opts) do
        Spectre.Prism.Adapter.ReqLLM.complete_plan(@prism_req_llm_provider, plan, opts)
      end

      if @prism_req_llm_embedding do
        @behaviour Spectre.Classifier.Embedding

        @impl Spectre.Classifier.Embedding
        def load(model, opts \\ []) do
          Spectre.Prism.Adapter.ReqLLM.load(
            @prism_req_llm_provider,
            model,
            opts,
            @prism_req_llm_embedding
          )
        end

        @impl Spectre.Classifier.Embedding
        def download(model, opts \\ []), do: load(model, opts)

        @impl Spectre.Classifier.Embedding
        def embed(input, opts \\ []) do
          Spectre.Prism.Adapter.ReqLLM.embed(@prism_req_llm_provider, input, opts)
        end
      end
    end
  end

  @doc false
  @spec complete(atom(), term(), term()) :: {:ok, SpectreResponse.t()} | {:error, Error.t()}
  def complete(provider, prompt, opts) when is_binary(prompt) do
    with :ok <- Client.validate_options(provider, opts) do
      prompt
      |> Prompt.parts()
      |> generate(provider, opts)
    end
  end

  def complete(provider, _prompt, _opts),
    do: {:error, Error.configuration(provider, :invalid_prompt)}

  @doc false
  @spec complete_plan(atom(), term(), term()) ::
          {:ok, SpectreResponse.t()} | {:error, Error.t()}
  def complete_plan(provider, %Spectre.Prompt.Plan{} = plan, opts) do
    with :ok <- Client.validate_options(provider, opts),
         :ok <- Client.validate_prompt_plan(provider, plan) do
      plan
      |> Prompt.parts()
      |> generate(provider, opts)
    end
  end

  def complete_plan(provider, _plan, _opts),
    do: {:error, Error.configuration(provider, :invalid_prompt_plan)}

  @doc false
  @spec load(atom(), term(), term(), keyword()) ::
          {:ok, pos_integer()} | {:error, Error.t()}
  def load(provider, model, opts, default_embedding)
      when is_binary(model) and model != "" do
    with :ok <- Client.validate_options(provider, opts) do
      default_dimensions = Keyword.get(default_embedding, :dimensions)

      case Client.dimensions(provider, opts, default_dimensions) do
        :probe -> probe_dimensions(provider, model, opts)
        result -> result
      end
    end
  end

  def load(provider, _model, _opts, _default_embedding),
    do: {:error, Error.configuration(provider, :invalid_model)}

  @doc false
  @spec embed(atom(), term(), term()) :: {:ok, term()} | {:error, Error.t()}
  def embed(provider, input, opts)
      when (is_binary(input) and input != "") or (is_list(input) and input != []) do
    with :ok <- Client.validate_options(provider, opts),
         :ok <- validate_embedding_input(provider, input),
         {:ok, model_spec} <- model_spec(provider, embedding_model(opts), opts),
         {:ok, req_opts} <- req_llm_options(provider, opts, @embedding_control_options),
         {:ok, client} <- req_llm_client(provider, opts, :embed) do
      client
      |> apply(:embed, [model_spec, input, req_opts])
      |> normalize_embedding(provider)
    end
  rescue
    _exception -> {:error, Error.transport(provider, :req_llm_exception)}
  catch
    :exit, _reason -> {:error, Error.transport(provider, :req_llm_exit)}
    _kind, _reason -> {:error, Error.transport(provider, :req_llm_failure)}
  end

  def embed(provider, _input, _opts),
    do: {:error, Error.configuration(provider, :invalid_embedding_input)}

  @spec generate(Prompt.parts(), atom(), keyword()) ::
          {:ok, SpectreResponse.t()} | {:error, Error.t()}
  defp generate(parts, provider, opts) do
    with {:ok, model_spec} <- model_spec(provider, Keyword.get(opts, :model), opts),
         {:ok, req_opts} <- req_llm_options(provider, opts, @generation_control_options),
         {:ok, client} <- req_llm_client(provider, opts, :generate_text) do
      req_opts = maybe_system_prompt(req_opts, parts.instructions)

      client
      |> apply(:generate_text, [model_spec, parts.input, req_opts])
      |> normalize_generation(provider, model_spec)
    end
  rescue
    _exception -> {:error, Error.transport(provider, :req_llm_exception)}
  catch
    :exit, _reason -> {:error, Error.transport(provider, :req_llm_exit)}
    _kind, _reason -> {:error, Error.transport(provider, :req_llm_failure)}
  end

  @spec model_spec(atom(), term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  defp model_spec(provider, model, opts) when is_binary(model) and model != "" do
    req_provider = Keyword.get(opts, :req_llm_provider, provider)

    if is_atom(req_provider) and not is_nil(req_provider) do
      spec = %{provider: req_provider, id: model}

      spec =
        case Keyword.get(opts, :base_url) do
          base_url when is_binary(base_url) and base_url != "" ->
            Map.put(spec, :base_url, base_url)

          nil ->
            spec

          _invalid ->
            :invalid
        end

      case {spec, Keyword.get(opts, :model_extra)} do
        {:invalid, _extra} ->
          {:error, Error.configuration(provider, :invalid_base_url)}

        {spec, nil} ->
          {:ok, spec}

        {spec, extra} when is_map(extra) ->
          {:ok, Map.put(spec, :extra, extra)}

        {_spec, _invalid} ->
          {:error, Error.configuration(provider, :invalid_model_extra)}
      end
    else
      {:error, Error.configuration(provider, :invalid_req_llm_provider)}
    end
  end

  defp model_spec(provider, _model, _opts),
    do: {:error, Error.configuration(provider, :invalid_model)}

  @spec req_llm_options(atom(), keyword(), [atom()]) ::
          {:ok, keyword()} | {:error, Error.t()}
  defp req_llm_options(provider, opts, control_options) do
    case runtime_api_key(opts, provider) do
      {:ok, key} ->
        req_opts =
          opts
          |> Keyword.drop(control_options)
          |> normalize_max_tokens()
          |> normalize_timeout()

        if is_binary(key),
          do: {:ok, Keyword.put(req_opts, :api_key, key)},
          else: {:ok, req_opts}

      {:error, _reason} = error ->
        error
    end
  end

  @spec runtime_api_key(keyword(), atom()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  defp runtime_api_key(opts, provider) do
    case Keyword.get(opts, :api_key) do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      nil ->
        case Client.optional_api_key(opts) do
          key when is_binary(key) -> {:ok, key}
          nil -> {:ok, nil}
        end

      _invalid ->
        {:error, Error.configuration(provider, :invalid_api_key)}
    end
  end

  @spec req_llm_client(atom(), keyword(), atom()) :: {:ok, module()} | {:error, Error.t()}
  defp req_llm_client(provider, opts, function) do
    client = Keyword.get(opts, :req_llm_module, ReqLLM)

    if is_atom(client) and Code.ensure_loaded?(client) and
         function_exported?(client, function, 3) do
      {:ok, client}
    else
      {:error, Error.configuration(provider, :req_llm_unavailable)}
    end
  end

  @spec normalize_generation(term(), atom(), map()) ::
          {:ok, SpectreResponse.t()} | {:error, Error.t()}
  defp normalize_generation({:ok, %ReqLLM.Response{} = response}, provider, model_spec) do
    build_response(
      ReqLLM.Response.text(response),
      response.id,
      response.usage,
      provider,
      response.model || model_spec.id,
      response.finish_reason
    )
  end

  defp normalize_generation({:ok, %{text: text} = response}, provider, model_spec) do
    build_response(
      text,
      Map.get(response, :id),
      Map.get(response, :usage, %{}),
      provider,
      Map.get(response, :model, model_spec.id),
      Map.get(response, :finish_reason)
    )
  end

  defp normalize_generation({:ok, text}, provider, model_spec) when is_binary(text) do
    build_response(text, nil, %{}, provider, model_spec.id, nil)
  end

  defp normalize_generation({:error, reason}, provider, _model_spec),
    do: {:error, normalize_error(provider, reason)}

  defp normalize_generation(_other, provider, _model_spec),
    do: {:error, Error.invalid_response(provider, :invalid_req_llm_response)}

  @spec build_response(term(), term(), term(), atom(), term(), term()) ::
          {:ok, SpectreResponse.t()} | {:error, Error.t()}
  defp build_response(text, request_id, usage, provider, model, finish_reason)
       when is_binary(text) and text != "" do
    {:ok,
     SpectreResponse.new(%{
       text: text,
       provider_request_id: request_id,
       usage: if(is_map(usage), do: usage, else: %{}),
       metadata: %{provider: provider, model: model, finish_reason: finish_reason}
     })}
  end

  defp build_response(_text, _request_id, _usage, provider, _model, _finish_reason),
    do: {:error, Error.invalid_response(provider, :missing_output_text)}

  @spec normalize_embedding(term(), atom()) :: {:ok, term()} | {:error, Error.t()}
  defp normalize_embedding({:ok, vector}, provider) do
    if valid_embedding?(vector),
      do: {:ok, normalize_embedding_numbers(vector)},
      else: {:error, Error.invalid_response(provider, :invalid_embedding_vector)}
  end

  defp normalize_embedding({:error, reason}, provider),
    do: {:error, normalize_error(provider, reason)}

  defp normalize_embedding(_other, provider),
    do: {:error, Error.invalid_response(provider, :invalid_req_llm_response)}

  @spec normalize_error(atom(), term()) :: Error.t()
  defp normalize_error(provider, %ReqLLM.Error.API.Timeout{}),
    do: Error.transport(provider, :timeout)

  defp normalize_error(provider, %ReqLLM.Error.API.Request{status: status} = reason)
       when is_integer(status) do
    Error.http(provider, status, safe_code(reason.provider_code))
  end

  defp normalize_error(provider, %ReqLLM.Error.API.Response{}),
    do: Error.invalid_response(provider, :req_llm_response_error)

  defp normalize_error(provider, %{class: class}) when class in [:invalid, :validation],
    do: Error.configuration(provider, :req_llm_configuration_error)

  defp normalize_error(provider, _reason),
    do: Error.transport(provider, :req_llm_request_failed)

  @spec safe_code(term()) :: atom() | String.t()
  defp safe_code(code) when is_atom(code), do: code

  defp safe_code(code) when is_binary(code) and byte_size(code) <= 128 do
    if Regex.match?(~r/\A[A-Za-z0-9._:\/-]+\z/, code),
      do: code,
      else: :provider_request_failed
  end

  defp safe_code(_code), do: :provider_request_failed

  @spec validate_embedding_input(atom(), term()) :: :ok | {:error, Error.t()}
  defp validate_embedding_input(_provider, input) when is_binary(input) and input != "", do: :ok

  defp validate_embedding_input(provider, inputs) when is_list(inputs) do
    if Enum.all?(inputs, &(is_binary(&1) and &1 != "")),
      do: :ok,
      else: {:error, Error.configuration(provider, :invalid_embedding_input)}
  end

  defp validate_embedding_input(provider, _input),
    do: {:error, Error.configuration(provider, :invalid_embedding_input)}

  @spec valid_embedding?(term()) :: boolean()
  defp valid_embedding?(vector) when is_list(vector) and vector != [] do
    Enum.all?(vector, &is_number/1) or
      Enum.all?(vector, fn item ->
        is_list(item) and item != [] and Enum.all?(item, &is_number/1)
      end)
  end

  defp valid_embedding?(_vector), do: false

  @spec normalize_embedding_numbers(list()) :: list()
  defp normalize_embedding_numbers([first | _rest] = vector) when is_list(first),
    do: Enum.map(vector, &Enum.map(&1, fn number -> number / 1 end))

  defp normalize_embedding_numbers(vector), do: Enum.map(vector, &(&1 / 1))

  @spec probe_dimensions(atom(), String.t(), keyword()) ::
          {:ok, pos_integer()} | {:error, Error.t()}
  defp probe_dimensions(provider, model, opts) do
    with {:ok, vector} <- embed(provider, "dimension probe", Keyword.put(opts, :model, model)) do
      {:ok, length(vector)}
    end
  end

  @spec embedding_model(keyword()) :: term()
  defp embedding_model(opts) do
    Keyword.get(
      opts,
      :model,
      Keyword.get(opts, :encoder_model, Keyword.get(opts, :embedding_model))
    )
  end

  @spec maybe_system_prompt(keyword(), String.t() | nil) :: keyword()
  defp maybe_system_prompt(opts, nil), do: opts

  defp maybe_system_prompt(opts, instructions),
    do: Keyword.put_new(opts, :system_prompt, instructions)

  @spec normalize_max_tokens(keyword()) :: keyword()
  defp normalize_max_tokens(opts) do
    case Keyword.fetch(opts, :max_tokens) do
      {:ok, _value} ->
        Keyword.drop(opts, [:max_output_tokens, :maximum_output_tokens])

      :error ->
        case Keyword.get(opts, :max_output_tokens, Keyword.get(opts, :maximum_output_tokens)) do
          nil ->
            opts

          value ->
            opts
            |> Keyword.drop([:max_output_tokens, :maximum_output_tokens])
            |> Keyword.put(:max_tokens, value)
        end
    end
  end

  @spec normalize_timeout(keyword()) :: keyword()
  defp normalize_timeout(opts) do
    case {Keyword.has_key?(opts, :receive_timeout), Keyword.pop(opts, :http_timeout)} do
      {true, {_http_timeout, opts}} -> opts
      {false, {nil, opts}} -> opts
      {false, {http_timeout, opts}} -> Keyword.put(opts, :receive_timeout, http_timeout)
    end
  end

  @spec maybe_keyword_put(keyword(), atom(), term()) :: keyword()
  defp maybe_keyword_put(opts, _key, nil), do: opts
  defp maybe_keyword_put(opts, key, value), do: Keyword.put(opts, key, value)
end
