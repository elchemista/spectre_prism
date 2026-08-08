defmodule Spectre.Prism.Adapters.Gemini do
  @moduledoc """
  Google Gemini Interactions API and embedding adapter.

  `GOOGLE_API_KEY` is preferred and `GEMINI_API_KEY` is used as a fallback.
  Text generation uses the Interactions API; embeddings use the documented
  `embedContent` endpoint. Both API versions and the base endpoint can be
  overridden.
  """

  @behaviour Spectre.Prism.Adapter
  @behaviour Spectre.LLM
  @behaviour Spectre.Classifier.Embedding

  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapter.Client
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.Prompt

  @provider :gemini
  @base_url "https://generativelanguage.googleapis.com"
  @api_key_envs ["GOOGLE_API_KEY", "GEMINI_API_KEY"]
  @embedding_dimensions %{
    "gemini-embedding-001" => 3072,
    "gemini-embedding-2" => 3072
  }

  @impl Spectre.Prism.Adapter
  def catalog do
    %{
      options: [api_key_env: @api_key_envs, base_url: @base_url],
      profiles: [
        fast: [
          model: "gemini-3.5-flash-lite",
          rank: 10,
          supports: [:text, :structured_output],
          context_window: 1_048_576,
          privacy: :cloud,
          cost_tier: :low,
          latency_tier: :low
        ],
        balanced: [
          model: "gemini-3.6-flash",
          rank: 20,
          supports: [:text, :structured_output],
          context_window: 1_048_576,
          privacy: :cloud,
          cost_tier: :medium,
          latency_tier: :medium
        ],
        deep: [
          model: "gemini-3.5-flash",
          rank: 30,
          supports: [:text, :structured_output],
          context_window: 1_048_576,
          privacy: :cloud,
          cost_tier: :high,
          latency_tier: :high
        ]
      ],
      classifier: :fast,
      embedding: [model: "gemini-embedding-2", dimensions: 768]
    }
  end

  @impl Spectre.LLM
  def complete(prompt, opts \\ [])

  def complete(prompt, opts) when is_binary(prompt) do
    with :ok <- Client.validate_options(@provider, opts) do
      prompt |> Prompt.parts() |> complete_parts(opts)
    end
  end

  def complete(_prompt, _opts),
    do: {:error, Error.configuration(@provider, :invalid_prompt)}

  @impl Spectre.LLM
  def complete_plan(%Spectre.Prompt.Plan{} = plan, opts) do
    with :ok <- Client.validate_options(@provider, opts),
         :ok <- Client.validate_prompt_plan(@provider, plan) do
      plan |> Prompt.parts() |> complete_parts(opts)
    end
  end

  def complete_plan(_plan, _opts),
    do: {:error, Error.configuration(@provider, :invalid_prompt_plan)}

  @impl Spectre.Classifier.Embedding
  def load(model, opts \\ [])

  def load(model, opts) when is_binary(model) and model != "" do
    with :ok <- Client.validate_options(@provider, opts) do
      load_dimensions(model, opts)
    end
  end

  def load(_model, _opts), do: {:error, Error.configuration(@provider, :invalid_model)}

  @impl Spectre.Classifier.Embedding
  def download(model, opts \\ []), do: load(model, opts)

  @spec load_dimensions(String.t(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  defp load_dimensions(model, opts) do
    case Client.dimensions(@provider, opts, Map.get(@embedding_dimensions, clean_model(model))) do
      :probe -> probe_dimensions(model, opts)
      result -> result
    end
  end

  @spec probe_dimensions(String.t(), keyword()) :: {:ok, pos_integer()} | {:error, term()}
  defp probe_dimensions(model, opts) do
    with {:ok, vector} <- embed("dimension probe", Keyword.put(opts, :model, model)) do
      {:ok, length(vector)}
    end
  end

  @impl Spectre.Classifier.Embedding
  def embed(text, opts \\ [])

  def embed(text, opts) when is_binary(text) and text != "" do
    with :ok <- Client.validate_options(@provider, opts) do
      embed_validated(text, opts)
    end
  end

  def embed(_text, _opts),
    do: {:error, Error.configuration(@provider, :invalid_embedding_input)}

  @spec embed_validated(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  defp embed_validated(text, opts) do
    model = Keyword.get(opts, :model, Keyword.get(opts, :encoder_model, "gemini-embedding-2"))
    version = Keyword.get(opts, :embedding_api_version, "v1beta")

    with {:ok, model} <- validate_segment(clean_model(model), :invalid_model),
         {:ok, version} <- validate_segment(version, :invalid_api_version),
         {:ok, key} <- Client.api_key(@provider, opts, @api_key_envs),
         {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(
               Keyword.get(opts, :base_url, @base_url),
               "/#{Client.path_segment(version)}/models/#{Client.path_segment(clean_model(model))}:embedContent"
             ),
             request_headers(key, opts),
             embedding_body(text, model, opts),
             opts
           ) do
      embedding_vector(body)
    end
  end

  @spec complete_parts(Prompt.parts(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  defp complete_parts(parts, opts) do
    version = Keyword.get(opts, :interaction_api_version, "v1beta")

    with {:ok, version} <- validate_segment(version, :invalid_api_version),
         {:ok, key} <- Client.api_key(@provider, opts, @api_key_envs),
         {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(
               Keyword.get(opts, :base_url, @base_url),
               "/#{Client.path_segment(version)}/interactions"
             ),
             request_headers(key, opts),
             interaction_body(parts, opts),
             opts
           ) do
      normalize_response(body)
    end
  end

  @spec interaction_body(Prompt.parts(), keyword()) :: map()
  defp interaction_body(parts, opts) do
    generation_config =
      opts
      |> Keyword.get(:generation_config, %{})
      |> Client.json()
      |> ensure_map()
      |> Client.put_option("temperature", opts, [:temperature])
      |> Client.put_option("top_p", opts, [:top_p])
      |> Client.put_option("thinking_level", opts, [:thinking_level])
      |> Client.put_option("max_output_tokens", opts, [
        :max_output_tokens,
        :maximum_output_tokens,
        :max_tokens
      ])

    %{
      "model" => Keyword.get(opts, :model, "gemini-3.6-flash"),
      "input" => parts.input
    }
    |> maybe_put("system_instruction", parts.instructions)
    |> maybe_put("generation_config", empty_to_nil(generation_config))
    |> Client.put_option("response_format", opts, [:response_format])
    |> Client.put_option("service_tier", opts, [:service_tier])
  end

  @spec embedding_body(String.t(), String.t(), keyword()) :: map()
  defp embedding_body(text, model, opts) do
    config =
      %{}
      |> Client.put_option("outputDimensionality", opts, [
        :dimensions,
        :output_dimensionality
      ])
      |> put_task_type(opts)
      |> Client.put_option("title", opts, [:title])
      |> Client.put_option("autoTruncate", opts, [:auto_truncate])

    %{
      "model" => "models/" <> clean_model(model),
      "content" => %{"parts" => [%{"text" => text}]}
    }
    |> maybe_put("embedContentConfig", empty_to_nil(config))
  end

  @spec request_headers(String.t(), keyword()) :: [{String.t(), String.t()}]
  defp request_headers(key, opts) do
    headers = [
      {"x-goog-api-key", key},
      {"content-type", "application/json"}
    ]

    headers = maybe_header(headers, "Api-Revision", Keyword.get(opts, :api_revision))
    Client.headers(headers, opts)
  end

  @spec normalize_response(term()) :: {:ok, Response.t()} | {:error, Error.t()}
  defp normalize_response(body) when is_map(body) do
    case Client.provider_error(body) do
      nil -> build_response(body)
      error -> {:error, Error.provider(@provider, Client.provider_error_code(error))}
    end
  end

  defp normalize_response(_body),
    do: {:error, Error.invalid_response(@provider, :response_not_an_object)}

  @spec build_response(map()) :: {:ok, Response.t()} | {:error, Error.t()}
  defp build_response(body) do
    text = Map.get(body, "output_text") || interaction_text(Map.get(body, "steps", []))

    if is_binary(text) and text != "" do
      {:ok,
       Response.new(%{
         text: text,
         provider_request_id: Map.get(body, "id"),
         usage: usage(Map.get(body, "usage", %{})),
         metadata: %{provider: @provider, model: Map.get(body, "model")}
       })}
    else
      {:error, Error.invalid_response(@provider, :missing_output_text)}
    end
  end

  @spec interaction_text(term()) :: String.t() | nil
  defp interaction_text(steps) when is_list(steps) do
    text =
      steps
      |> Enum.reverse()
      |> Enum.find_value(fn
        %{"type" => "model_output", "content" => content} when is_list(content) ->
          content
          |> Enum.flat_map(fn
            %{"type" => "text", "text" => text} when is_binary(text) -> [text]
            %{"text" => text} when is_binary(text) -> [text]
            _part -> []
          end)
          |> Enum.join("")
          |> case do
            "" -> nil
            output -> output
          end

        _step ->
          nil
      end)

    if text == "", do: nil, else: text
  end

  defp interaction_text(_steps), do: nil

  @spec embedding_vector(term()) :: {:ok, [float()]} | {:error, Error.t()}
  defp embedding_vector(%{"embedding" => %{"values" => vector}}),
    do: validate_vector(vector)

  defp embedding_vector(%{"embeddings" => [%{"values" => vector} | _rest]}),
    do: validate_vector(vector)

  defp embedding_vector(body) when is_map(body) do
    case Client.provider_error(body) do
      nil -> {:error, Error.invalid_response(@provider, :missing_embedding_vector)}
      error -> {:error, Error.provider(@provider, Client.provider_error_code(error))}
    end
  end

  defp embedding_vector(_body),
    do: {:error, Error.invalid_response(@provider, :embedding_response_not_an_object)}

  @spec validate_vector(term()) :: {:ok, [float()]} | {:error, Error.t()}
  defp validate_vector(vector) when is_list(vector) and vector != [] do
    if Enum.all?(vector, &is_number/1),
      do: {:ok, Enum.map(vector, &(&1 / 1))},
      else: {:error, Error.invalid_response(@provider, :invalid_embedding_vector)}
  end

  defp validate_vector(_vector),
    do: {:error, Error.invalid_response(@provider, :invalid_embedding_vector)}

  @spec usage(term()) :: map()
  defp usage(usage) when is_map(usage) do
    input = Client.token_count(usage, "total_input_tokens")
    output = Client.token_count(usage, "total_output_tokens")

    %{
      input_tokens: input,
      output_tokens: output,
      reasoning_tokens: Client.token_count(usage, "total_thought_tokens"),
      total_tokens: Client.token_count(usage, "total_tokens", input + output)
    }
  end

  defp usage(_usage), do: %{}

  @spec clean_model(String.t()) :: String.t()
  defp clean_model("models/" <> model), do: model
  defp clean_model(model), do: model

  @spec ensure_map(term()) :: map()
  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  @spec empty_to_nil(map()) :: map() | nil
  defp empty_to_nil(map) when map_size(map) == 0, do: nil
  defp empty_to_nil(map), do: map

  @spec maybe_put(map(), String.t(), term()) :: map()
  defp maybe_put(body, _key, nil), do: body
  defp maybe_put(body, key, value), do: Map.put(body, key, value)

  @spec maybe_header(list(), String.t(), term()) :: list()
  defp maybe_header(headers, _name, nil), do: headers
  defp maybe_header(headers, name, value) when is_binary(value), do: headers ++ [{name, value}]
  defp maybe_header(headers, _name, _value), do: headers

  @spec put_task_type(map(), keyword()) :: map()
  defp put_task_type(config, opts) do
    case Keyword.get(opts, :task_type) do
      nil ->
        config

      task when is_atom(task) ->
        Map.put(config, "taskType", task |> to_string() |> String.upcase())

      task when is_binary(task) ->
        Map.put(config, "taskType", task)

      task ->
        Map.put(config, "taskType", Client.json(task))
    end
  end

  @spec validate_segment(term(), atom()) :: {:ok, String.t()} | {:error, Error.t()}
  defp validate_segment(value, _error) when is_binary(value) and value != "" do
    {:ok, value}
  end

  defp validate_segment(_value, error),
    do: {:error, Error.configuration(@provider, error)}
end
