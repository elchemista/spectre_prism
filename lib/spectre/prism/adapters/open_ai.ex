defmodule Spectre.Prism.Adapters.OpenAI do
  @moduledoc """
  OpenAI Responses API and embeddings adapter.

  Credentials are read from `OPENAI_API_KEY` by default. The catalog maps
  `:fast`, `:balanced`, and `:deep` to the Luna, Terra, and Sol tiers of the
  GPT-5.6 family. Every model and endpoint remains overridable at registration
  or call time.
  """

  @behaviour Spectre.Prism.Adapter
  @behaviour Spectre.LLM
  @behaviour Spectre.Classifier.Embedding

  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapter.Client
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapter.Prompt

  @provider :openai
  @base_url "https://api.openai.com/v1"
  @embedding_dimensions %{
    "text-embedding-3-small" => 1536,
    "text-embedding-3-large" => 3072,
    "text-embedding-ada-002" => 1536
  }

  @impl Spectre.Prism.Adapter
  def catalog do
    %{
      options: [api_key_env: "OPENAI_API_KEY", base_url: @base_url],
      profiles: [
        fast: [
          model: "gpt-5.6-luna",
          rank: 10,
          supports: [:text, :structured_output],
          context_window: 1_050_000,
          privacy: :cloud,
          cost_tier: :low,
          latency_tier: :low
        ],
        balanced: [
          model: "gpt-5.6-terra",
          rank: 20,
          supports: [:text, :structured_output],
          context_window: 1_050_000,
          privacy: :cloud,
          cost_tier: :medium,
          latency_tier: :medium
        ],
        deep: [
          model: "gpt-5.6-sol",
          rank: 30,
          supports: [:text, :structured_output],
          context_window: 1_050_000,
          privacy: :cloud,
          cost_tier: :high,
          latency_tier: :high
        ]
      ],
      classifier: :fast,
      embedding: [model: "text-embedding-3-small", dimensions: 1536]
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
    case Keyword.get(opts, :dimensions, Map.get(@embedding_dimensions, model)) do
      dimensions when is_integer(dimensions) and dimensions > 0 ->
        {:ok, dimensions}

      _unknown ->
        with {:ok, vector} <- embed("dimension probe", Keyword.put(opts, :model, model)) do
          {:ok, length(vector)}
        end
    end
  end

  @impl Spectre.Classifier.Embedding
  def download(model, opts \\ []) when is_binary(model) and is_list(opts),
    do: load(model, opts)

  @impl Spectre.Classifier.Embedding
  def embed(text, opts \\ []) when is_binary(text) and is_list(opts) do
    with {:ok, key} <- Client.api_key(@provider, opts, "OPENAI_API_KEY"),
         {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(Keyword.get(opts, :base_url, @base_url), "/embeddings"),
             request_headers(key, opts),
             embedding_body(text, opts),
             opts
           ) do
      embedding_vector(body)
    end
  end

  @spec complete_parts(Prompt.parts(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  defp complete_parts(parts, opts) do
    with {:ok, key} <- Client.api_key(@provider, opts, "OPENAI_API_KEY"),
         {:ok, body, _headers} <-
           Client.post(
             @provider,
             Client.url(Keyword.get(opts, :base_url, @base_url), "/responses"),
             request_headers(key, opts),
             response_body(parts, opts),
             opts
           ) do
      normalize_response(body)
    end
  end

  @spec response_body(Prompt.parts(), keyword()) :: map()
  defp response_body(parts, opts) do
    %{
      "model" => Keyword.get(opts, :model, "gpt-5.6-terra"),
      "input" => parts.input
    }
    |> maybe_put("instructions", parts.instructions)
    |> Client.put_option("max_output_tokens", opts, [
      :max_output_tokens,
      :maximum_output_tokens,
      :max_tokens
    ])
    |> Client.put_option("reasoning", opts, [:reasoning])
    |> maybe_reasoning_effort(opts)
    |> Client.put_option("temperature", opts, [:temperature])
    |> Client.put_option("top_p", opts, [:top_p])
    |> Client.put_option("text", opts, [:text])
    |> Client.put_option("store", opts, [:store])
    |> Client.put_option("service_tier", opts, [:service_tier])
  end

  @spec embedding_body(String.t(), keyword()) :: map()
  defp embedding_body(text, opts) do
    %{
      "model" => Keyword.get(opts, :model, "text-embedding-3-small"),
      "input" => text,
      "encoding_format" => "float"
    }
    |> Client.put_option("dimensions", opts, [:dimensions])
    |> Client.put_option("user", opts, [:user])
  end

  @spec request_headers(String.t(), keyword()) :: [{String.t(), String.t()}]
  defp request_headers(key, opts) do
    Client.headers(
      [
        {"authorization", "Bearer " <> key},
        {"content-type", "application/json"}
      ],
      opts
    )
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
    text = Map.get(body, "output_text") || output_text(Map.get(body, "output", []))

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

  @spec output_text(term()) :: String.t() | nil
  defp output_text(output) when is_list(output) do
    text =
      output
      |> Enum.flat_map(fn
        %{"type" => "message", "content" => content} when is_list(content) -> content
        %{"content" => content} when is_list(content) -> content
        _item -> []
      end)
      |> Enum.flat_map(fn
        %{"type" => "output_text", "text" => text} when is_binary(text) -> [text]
        %{"text" => text} when is_binary(text) -> [text]
        _content -> []
      end)
      |> Enum.join("")

    if text == "", do: nil, else: text
  end

  defp output_text(_output), do: nil

  @spec embedding_vector(term()) :: {:ok, [float()]} | {:error, Error.t()}
  defp embedding_vector(%{"data" => [%{"embedding" => vector} | _rest]})
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

  @spec usage(term()) :: map()
  defp usage(usage) when is_map(usage) do
    %{
      input_tokens: Map.get(usage, "input_tokens", 0),
      output_tokens: Map.get(usage, "output_tokens", 0),
      total_tokens: Map.get(usage, "total_tokens", 0)
    }
  end

  defp usage(_usage), do: %{}

  @spec maybe_put(map(), String.t(), term()) :: map()
  defp maybe_put(body, _key, nil), do: body
  defp maybe_put(body, key, value), do: Map.put(body, key, value)

  @spec maybe_reasoning_effort(map(), keyword()) :: map()
  defp maybe_reasoning_effort(%{"reasoning" => _reasoning} = body, _opts), do: body

  defp maybe_reasoning_effort(body, opts) do
    case Keyword.get(opts, :reasoning_effort) do
      nil -> body
      effort -> Map.put(body, "reasoning", %{"effort" => Client.json(effort)})
    end
  end
end
