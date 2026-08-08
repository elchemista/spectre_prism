defmodule Spectre.Prism.Adapters.OpenRouter do
  @moduledoc """
  OpenRouter Chat Completions and embeddings adapter.

  Credentials are read from `OPENROUTER_API_KEY`. The bundled profile catalog
  uses the GPT-5.6 Luna, Terra, and Sol routes, while `models:` overrides let a
  registration select any OpenRouter model without changing the adapter.
  """

  @behaviour Spectre.Prism.Adapter
  @behaviour Spectre.LLM
  @behaviour Spectre.Classifier.Embedding

  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapter.Client
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.Prompt

  @provider :openrouter
  @base_url "https://openrouter.ai/api/v1"
  @embedding_dimensions %{
    "openai/text-embedding-3-small" => 1536,
    "openai/text-embedding-3-large" => 3072
  }

  @impl Spectre.Prism.Adapter
  def catalog do
    %{
      options: [api_key_env: "OPENROUTER_API_KEY", base_url: @base_url],
      profiles: [
        fast: [
          model: "openai/gpt-5.6-luna",
          rank: 10,
          supports: [:text, :structured_output],
          context_window: 1_050_000,
          privacy: :cloud,
          cost_tier: :low,
          latency_tier: :low
        ],
        balanced: [
          model: "openai/gpt-5.6-terra",
          rank: 20,
          supports: [:text, :structured_output],
          context_window: 1_050_000,
          privacy: :cloud,
          cost_tier: :medium,
          latency_tier: :medium
        ],
        deep: [
          model: "openai/gpt-5.6-sol",
          rank: 30,
          supports: [:text, :structured_output],
          context_window: 1_050_000,
          privacy: :cloud,
          cost_tier: :high,
          latency_tier: :high
        ]
      ],
      classifier: :fast,
      embedding: [model: "openai/text-embedding-3-small", dimensions: 1536]
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
    case Client.dimensions(@provider, opts, Map.get(@embedding_dimensions, model)) do
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
  def embed(input, opts \\ [])

  def embed(text, opts) when is_binary(text) and text != "" do
    with :ok <- Client.validate_options(@provider, opts),
         {:ok, [vector]} <- request_embeddings(text, 1, opts),
         do: {:ok, vector}
  end

  def embed(texts, opts) when is_list(texts) do
    with :ok <- Client.validate_options(@provider, opts) do
      if texts != [] and Enum.all?(texts, &(is_binary(&1) and &1 != "")) do
        request_embeddings(texts, length(texts), opts)
      else
        {:error, Error.configuration(@provider, :invalid_embedding_input)}
      end
    end
  end

  def embed(_input, _opts),
    do: {:error, Error.configuration(@provider, :invalid_embedding_input)}

  @spec request_embeddings(String.t() | [String.t()], pos_integer(), keyword()) ::
          {:ok, [[float()]]} | {:error, Error.t()}
  defp request_embeddings(input, expected_count, opts) do
    with {:ok, key} <- Client.api_key(@provider, opts, "OPENROUTER_API_KEY"),
         {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(Keyword.get(opts, :base_url, @base_url), "/embeddings"),
             request_headers(key, opts),
             embedding_body(input, opts),
             opts
           ) do
      Client.embedding_vectors(@provider, body, expected_count)
    end
  end

  @spec complete_parts(Prompt.parts(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  defp complete_parts(parts, opts) do
    with {:ok, key} <- Client.api_key(@provider, opts, "OPENROUTER_API_KEY"),
         {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(Keyword.get(opts, :base_url, @base_url), "/chat/completions"),
             request_headers(key, opts),
             chat_body(parts, opts),
             opts
           ) do
      normalize_response(body)
    end
  end

  @spec chat_body(Prompt.parts(), keyword()) :: map()
  defp chat_body(parts, opts) do
    %{
      "model" => Keyword.get(opts, :model, "openai/gpt-5.6-terra"),
      "messages" => Prompt.messages(parts),
      "stream" => false
    }
    |> Client.put_option("max_tokens", opts, [
      :max_tokens,
      :max_output_tokens,
      :maximum_output_tokens
    ])
    |> Client.put_option("reasoning", opts, [:reasoning])
    |> Client.put_option("temperature", opts, [:temperature])
    |> Client.put_option("top_p", opts, [:top_p])
    |> Client.put_option("response_format", opts, [:response_format])
    |> Client.put_option("seed", opts, [:seed])
    |> Client.put_option("provider", opts, [:provider_routing])
  end

  @spec embedding_body(String.t() | [String.t()], keyword()) :: map()
  defp embedding_body(input, opts) do
    %{
      "model" => Keyword.get(opts, :model, "openai/text-embedding-3-small"),
      "input" => input,
      "encoding_format" => "float"
    }
    |> Client.put_option("encoding_format", opts, [:encoding_format])
    |> Client.put_option("dimensions", opts, [:dimensions])
  end

  @spec request_headers(String.t(), keyword()) :: [{String.t(), String.t()}]
  defp request_headers(key, opts) do
    defaults = [
      {"authorization", "Bearer " <> key},
      {"content-type", "application/json"}
    ]

    defaults = maybe_header(defaults, "HTTP-Referer", Keyword.get(opts, :site_url))
    defaults = maybe_header(defaults, "X-OpenRouter-Title", Keyword.get(opts, :app_name))
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
  defp build_response(body) do
    text = body |> first_choice() |> message_text()

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

  @spec message_text(term()) :: String.t() | nil
  defp message_text(%{"message" => %{"content" => content}}) when is_binary(content),
    do: content

  defp message_text(%{"message" => %{"content" => content}}) when is_list(content) do
    text =
      content
      |> Enum.flat_map(fn
        %{"type" => "text", "text" => text} when is_binary(text) -> [text]
        %{"text" => text} when is_binary(text) -> [text]
        _part -> []
      end)
      |> Enum.join("")

    if text == "", do: nil, else: text
  end

  defp message_text(_choice), do: nil

  @spec usage(term()) :: map()
  defp usage(usage) when is_map(usage) do
    input = Client.token_count(usage, "prompt_tokens")
    output = Client.token_count(usage, "completion_tokens")

    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: Client.token_count(usage, "total_tokens", input + output)
    }
  end

  defp usage(_usage), do: %{}

  @spec maybe_header(list(), String.t(), term()) :: list()
  defp maybe_header(headers, _name, nil), do: headers
  defp maybe_header(headers, name, value) when is_binary(value), do: headers ++ [{name, value}]
  defp maybe_header(headers, _name, _value), do: headers

  @spec first_choice(term()) :: term()
  defp first_choice(%{"choices" => [choice | _rest]}), do: choice
  defp first_choice(_body), do: nil
end
