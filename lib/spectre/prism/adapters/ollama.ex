defmodule Spectre.Prism.Adapters.Ollama do
  @moduledoc """
  Local Ollama chat and embedding adapter.

  The default endpoint is `http://127.0.0.1:11434`. Profiles use increasing
  Qwen 3.5 sizes and are marked `:local`, so Prism can satisfy
  `privacy: :local_only` requests. Models must be pulled by the host before
  normal inference; `download/2` is available for explicit classifier setup.
  """

  @behaviour Spectre.Prism.Adapter
  @behaviour Spectre.LLM
  @behaviour Spectre.Classifier.Embedding

  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapter.Client
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.Prompt

  @provider :ollama
  @base_url "http://127.0.0.1:11434"

  @impl Spectre.Prism.Adapter
  def catalog do
    %{
      options: [base_url: @base_url],
      profiles: [
        fast: [
          model: "qwen3.5:0.8b",
          rank: 10,
          supports: [:text, :structured_output],
          context_window: 262_144,
          privacy: :local,
          cost_tier: :low,
          latency_tier: :low,
          adapter_opts: [think: false]
        ],
        balanced: [
          model: "qwen3.5:9b",
          rank: 20,
          supports: [:text, :structured_output],
          context_window: 262_144,
          privacy: :local,
          cost_tier: :medium,
          latency_tier: :medium,
          adapter_opts: [think: "low"]
        ],
        deep: [
          model: "qwen3.5:35b",
          rank: 30,
          supports: [:text, :structured_output],
          context_window: 262_144,
          privacy: :local,
          cost_tier: :high,
          latency_tier: :high,
          adapter_opts: [think: "high"]
        ]
      ],
      classifier: :fast,
      embedding: [model: "embeddinggemma"]
    }
  end

  @impl Spectre.LLM
  def complete(prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    prompt |> Prompt.parts() |> complete_parts(opts)
  end

  @impl Spectre.LLM
  def complete_plan(%Spectre.Prompt.Plan{} = plan, opts) when is_list(opts) do
    plan |> Prompt.parts() |> complete_parts(opts)
  end

  @impl Spectre.Classifier.Embedding
  def load(model, opts \\ []) when is_binary(model) and is_list(opts) do
    case Keyword.get(opts, :dimensions) do
      dimensions when is_integer(dimensions) and dimensions > 0 ->
        {:ok, dimensions}

      _unknown ->
        with {:ok, vector} <- embed("dimension probe", Keyword.put(opts, :model, model)) do
          {:ok, length(vector)}
        end
    end
  end

  @impl Spectre.Classifier.Embedding
  def download(model, opts \\ []) when is_binary(model) and is_list(opts) do
    with {:ok, _body, _headers} <-
           Client.post(
             @provider,
             Client.url(Keyword.get(opts, :base_url, @base_url), "/api/pull"),
             request_headers(opts),
             %{"model" => model, "stream" => false},
             opts
           ) do
      load(model, opts)
    end
  end

  @impl Spectre.Classifier.Embedding
  def embed(text, opts \\ []) when is_binary(text) and is_list(opts) do
    with {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(Keyword.get(opts, :base_url, @base_url), "/api/embed"),
             request_headers(opts),
             embedding_body(text, opts),
             opts
           ) do
      embedding_vector(body)
    end
  end

  @spec complete_parts(Prompt.parts(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  defp complete_parts(parts, opts) do
    with {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(Keyword.get(opts, :base_url, @base_url), "/api/chat"),
             request_headers(opts),
             chat_body(parts, opts),
             opts
           ) do
      normalize_response(body)
    end
  end

  @spec chat_body(Prompt.parts(), keyword()) :: map()
  defp chat_body(parts, opts) do
    options =
      opts
      |> Keyword.get(:options, %{})
      |> Client.json()
      |> ensure_map()
      |> maybe_map_option("temperature", opts, [:temperature])
      |> maybe_map_option("top_p", opts, [:top_p])
      |> maybe_map_option("num_predict", opts, [
        :num_predict,
        :max_tokens,
        :max_output_tokens,
        :maximum_output_tokens
      ])
      |> maybe_map_option("seed", opts, [:seed])

    %{
      "model" => Keyword.get(opts, :model, "qwen3.5:9b"),
      "messages" => Prompt.messages(parts),
      "stream" => false,
      "options" => options
    }
    |> Client.put_option("think", opts, [:think])
    |> Client.put_option("format", opts, [:format, :response_format])
    |> Client.put_option("keep_alive", opts, [:keep_alive])
  end

  @spec embedding_body(String.t(), keyword()) :: map()
  defp embedding_body(text, opts) do
    %{
      "model" => Keyword.get(opts, :model, Keyword.get(opts, :encoder_model, "embeddinggemma")),
      "input" => text
    }
    |> Client.put_option("truncate", opts, [:truncate])
    |> Client.put_option("dimensions", opts, [:dimensions])
    |> Client.put_option("keep_alive", opts, [:keep_alive])
  end

  @spec request_headers(keyword()) :: [{String.t(), String.t()}]
  defp request_headers(opts) do
    defaults = [{"content-type", "application/json"}]

    defaults =
      case Client.optional_api_key(opts) do
        key when is_binary(key) -> defaults ++ [{"authorization", "Bearer " <> key}]
        nil -> defaults
      end

    Client.headers(defaults, opts)
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
  defp build_response(%{"message" => %{"content" => text}} = body)
       when is_binary(text) and text != "" do
    prompt_tokens = Map.get(body, "prompt_eval_count", 0)
    output_tokens = Map.get(body, "eval_count", 0)

    {:ok,
     Response.new(%{
       text: text,
       provider_request_id: nil,
       usage: %{
         input_tokens: prompt_tokens,
         output_tokens: output_tokens,
         total_tokens: prompt_tokens + output_tokens
       },
       metadata: %{provider: @provider, model: Map.get(body, "model")}
     })}
  end

  defp build_response(_body),
    do: {:error, Error.invalid_response(@provider, :missing_output_text)}

  @spec embedding_vector(term()) :: {:ok, [float()]} | {:error, Error.t()}
  defp embedding_vector(%{"embeddings" => [vector | _rest]})
       when is_list(vector) and vector != [] do
    if Enum.all?(vector, &is_number/1),
      do: {:ok, Enum.map(vector, &(&1 / 1))},
      else: {:error, Error.invalid_response(@provider, :invalid_embedding_vector)}
  end

  defp embedding_vector(body) when is_map(body) do
    case Client.provider_error(body) do
      nil -> {:error, Error.invalid_response(@provider, :missing_embedding_vector)}
      error -> {:error, Error.provider(@provider, Client.provider_error_code(error))}
    end
  end

  defp embedding_vector(_body),
    do: {:error, Error.invalid_response(@provider, :embedding_response_not_an_object)}

  @spec ensure_map(term()) :: map()
  defp ensure_map(value) when is_map(value), do: value
  defp ensure_map(_value), do: %{}

  @spec maybe_map_option(map(), String.t(), keyword(), [atom()]) :: map()
  defp maybe_map_option(map, target, opts, sources) do
    Client.put_option(map, target, opts, sources)
  end
end
