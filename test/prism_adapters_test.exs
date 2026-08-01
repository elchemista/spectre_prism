defmodule Spectre.Prism.AdaptersTest.Transport do
  @moduledoc false

  @behaviour Spectre.Prism.Adapter.Transport

  @impl true
  def request(method, url, headers, body, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:adapter_request, method, url, headers, body})
    Keyword.fetch!(opts, :transport_reply)
  end
end

defmodule Spectre.Prism.AdaptersTest do
  use ExUnit.Case, async: true

  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.Adapters.Gemini
  alias Spectre.Prism.Adapters.Ollama
  alias Spectre.Prism.Adapters.OpenAI
  alias Spectre.Prism.Adapters.OpenRouter
  alias Spectre.Prism.AdaptersTest.Transport
  alias Spectre.Prism.Registry
  alias Spectre.Router.LLMClassifier

  test "OpenAI maps Responses and embeddings to Spectre contracts" do
    reply =
      ok(%{
        "id" => "resp_1",
        "model" => "gpt-5.6-terra",
        "output" => [
          %{"type" => "message", "content" => [%{"type" => "output_text", "text" => "ok"}]}
        ],
        "usage" => %{"input_tokens" => 3, "output_tokens" => 2, "total_tokens" => 5}
      })

    assert {:ok, %Response{text: "ok", provider_request_id: "resp_1"} = response} =
             OpenAI.complete("hello", request_opts(reply, model: "gpt-5.6-terra"))

    assert response.usage.total_tokens == 5

    assert_receive {:adapter_request, :post, "https://api.openai.com/v1/responses", headers, body}

    assert header(headers, "authorization") == "Bearer test-key"
    assert body == %{"input" => "hello", "model" => "gpt-5.6-terra"}

    assert {:ok, [0.25, 0.75]} =
             OpenAI.embed(
               "vector me",
               request_opts(ok(%{"data" => [%{"embedding" => [0.25, 0.75]}]}),
                 model: "text-embedding-3-small",
                 dimensions: 2
               )
             )

    assert_receive {:adapter_request, :post, "https://api.openai.com/v1/embeddings", _headers,
                    embedding_body}

    assert embedding_body["input"] == "vector me"
    assert embedding_body["dimensions"] == 2
    assert {:ok, 1536} = OpenAI.download("text-embedding-3-small")
  end

  test "OpenRouter maps chat completions and hosted embeddings" do
    reply =
      ok(%{
        "id" => "chat_1",
        "model" => "openai/gpt-5.6-luna",
        "choices" => [%{"message" => %{"content" => "routed"}}],
        "usage" => %{"prompt_tokens" => 4, "completion_tokens" => 1, "total_tokens" => 5}
      })

    assert {:ok, %Response{text: "routed"}} =
             OpenRouter.complete(
               "hello",
               request_opts(reply,
                 model: "openai/gpt-5.6-luna",
                 site_url: "https://example.test",
                 app_name: "Prism test"
               )
             )

    assert_receive {:adapter_request, :post, "https://openrouter.ai/api/v1/chat/completions",
                    headers, body}

    assert header(headers, "http-referer") == "https://example.test"
    assert header(headers, "x-openrouter-title") == "Prism test"
    assert body["messages"] == [%{"role" => "user", "content" => "hello"}]

    assert {:ok, [1.0, 2.0]} =
             OpenRouter.embed(
               "vector me",
               request_opts(ok(%{"data" => [%{"embedding" => [1, 2]}]}),
                 model: "openai/text-embedding-3-small"
               )
             )

    assert_receive {:adapter_request, :post, "https://openrouter.ai/api/v1/embeddings", _headers,
                    _body}
  end

  test "OpenRouter embeds batches in one request, preserving provider index order" do
    reply =
      ok(%{
        "data" => [
          %{"index" => 1, "embedding" => [3, 4]},
          %{"index" => 0, "embedding" => [1, 2]}
        ]
      })

    assert {:ok, [[1.0, 2.0], [3.0, 4.0]]} =
             OpenRouter.embed(
               ["first", "second"],
               request_opts(reply,
                 model: "perplexity/pplx-embed-v1-0.6b",
                 dimensions: 2,
                 encoding_format: "base64"
               )
             )

    assert_receive {:adapter_request, :post, "https://openrouter.ai/api/v1/embeddings", _headers,
                    body}

    assert body["input"] == ["first", "second"]
    assert body["model"] == "perplexity/pplx-embed-v1-0.6b"
    assert body["dimensions"] == 2
    assert body["encoding_format"] == "base64"
  end

  test "OpenRouter batch embedding rejects invalid input and count mismatches" do
    assert {:error,
            %Error{provider: :openrouter, kind: :configuration, code: :invalid_embedding_input}} =
             OpenRouter.embed([], request_opts(ok(%{"data" => []})))

    assert {:error,
            %Error{provider: :openrouter, kind: :configuration, code: :invalid_embedding_input}} =
             OpenRouter.embed(["one", :two], request_opts(ok(%{"data" => []})))

    reply = ok(%{"data" => [%{"index" => 0, "embedding" => [1, 2]}]})

    assert {:error, %Error{kind: :invalid_response, code: :embedding_count_mismatch}} =
             OpenRouter.embed(["first", "second"], request_opts(reply, model: "any/model"))
  end

  test "OpenAI embeds batches with encoding_format passthrough" do
    reply =
      ok(%{
        "data" => [
          %{"index" => 0, "embedding" => [0.25, 0.75]},
          %{"index" => 1, "embedding" => [0.5, 0.5]}
        ]
      })

    assert {:ok, [[0.25, 0.75], [0.5, 0.5]]} =
             OpenAI.embed(
               ["alpha", "beta"],
               request_opts(reply,
                 model: "text-embedding-3-small",
                 dimensions: 2,
                 encoding_format: "float"
               )
             )

    assert_receive {:adapter_request, :post, "https://api.openai.com/v1/embeddings", _headers,
                    body}

    assert body["input"] == ["alpha", "beta"]
    assert body["encoding_format"] == "float"
    assert body["dimensions"] == 2
  end

  test "Ollama uses local chat, embed, and pull endpoints without credentials" do
    reply =
      ok(%{
        "model" => "qwen3.5:9b",
        "message" => %{"content" => "local"},
        "prompt_eval_count" => 6,
        "eval_count" => 2
      })

    opts =
      request_opts(reply,
        api_key: nil,
        model: "qwen3.5:9b",
        think: "low",
        max_tokens: 12
      )

    assert {:ok, %Response{text: "local", usage: %{total_tokens: 8}}} =
             Ollama.complete("hello", opts)

    assert_receive {:adapter_request, :post, "http://127.0.0.1:11434/api/chat", headers, body}
    assert header(headers, "authorization") == nil
    assert body["think"] == "low"
    assert body["options"]["num_predict"] == 12

    assert {:ok, [0.1, 0.2]} =
             Ollama.embed(
               "vector me",
               request_opts(ok(%{"embeddings" => [[0.1, 0.2]]}),
                 api_key: nil,
                 model: "embeddinggemma"
               )
             )

    assert_receive {:adapter_request, :post, "http://127.0.0.1:11434/api/embed", _headers,
                    %{"input" => "vector me", "model" => "embeddinggemma"}}

    assert {:ok, 768} =
             Ollama.download(
               "embeddinggemma",
               request_opts(ok(%{"status" => "success"}), api_key: nil, dimensions: 768)
             )

    assert_receive {:adapter_request, :post, "http://127.0.0.1:11434/api/pull", _headers,
                    %{"model" => "embeddinggemma", "stream" => false}}
  end

  test "Gemini uses the current Interactions and EmbedContent shapes" do
    reply =
      ok(%{
        "id" => "interaction_1",
        "model" => "gemini-3.6-flash",
        "steps" => [
          %{"type" => "model_output", "content" => [%{"type" => "text", "text" => "gemini"}]}
        ],
        "usage" => %{"total_input_tokens" => 3, "total_output_tokens" => 2, "total_tokens" => 5}
      })

    assert {:ok, %Response{text: "gemini", provider_request_id: "interaction_1"}} =
             Gemini.complete(
               "hello",
               request_opts(reply, model: "gemini-3.6-flash", thinking_level: :low)
             )

    assert_receive {:adapter_request, :post,
                    "https://generativelanguage.googleapis.com/v1beta/interactions", headers,
                    body}

    assert header(headers, "x-goog-api-key") == "test-key"
    assert body["generation_config"] == %{"thinking_level" => "low"}

    assert {:ok, [0.5, 0.25]} =
             Gemini.embed(
               "vector me",
               request_opts(ok(%{"embedding" => %{"values" => [0.5, 0.25]}}),
                 model: "gemini-embedding-2",
                 dimensions: 768,
                 task_type: :retrieval_query
               )
             )

    assert_receive {:adapter_request, :post,
                    "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-2:embedContent",
                    _headers, embedding_body}

    assert embedding_body["embedContentConfig"] == %{
             "outputDimensionality" => 768,
             "taskType" => "RETRIEVAL_QUERY"
           }

    assert {:ok, 768} = Gemini.download("gemini-embedding-2", dimensions: 768)
  end

  test "adapter failures are structured, retry-aware, and sanitized" do
    assert {:error,
            %Error{
              provider: :openai,
              kind: :configuration,
              code: :missing_api_key,
              retryable?: false
            }} =
             OpenAI.complete("private prompt", api_key_env: "PRISM_MISSING_TEST_API_KEY")

    assert {:error,
            %Error{
              provider: :openai,
              kind: :http,
              code: "rate_limit_exceeded",
              status: 429,
              retryable?: true
            } = error} =
             OpenAI.complete(
               "private prompt",
               request_opts(
                 {:ok, 429, [],
                  %{"error" => %{"code" => "rate_limit_exceeded", "message" => "secret"}}}
               )
             )

    refute inspect(error) =~ "private prompt"
    refute inspect(error) =~ "secret"
    refute inspect(error) =~ "test-key"
  end

  test "a registry-provided model runs through Spectre's LLM classifier boundary" do
    assert {:ok, registry} = Registry.build([{:openai, OpenAI, [embedding: false]}])

    reply =
      ok(%{
        "id" => "classifier_1",
        "model" => "gpt-5.6-luna",
        "output_text" => "GREETING"
      })

    opts =
      request_opts(reply)
      |> Keyword.put(:classifier, Registry.classifier(registry))

    assert {:ok, route} =
             LLMClassifier.classify(
               "ciao",
               [:GREETING, :OTHER],
               opts
             )

    assert route.label == :GREETING
    assert route.strategy == :llm_classifier

    assert_receive {:adapter_request, :post, "https://api.openai.com/v1/responses", _headers,
                    body}

    assert body["model"] == "gpt-5.6-luna"
    assert body["max_output_tokens"] == 8
    assert body["input"] =~ "Available labels:"
  end

  defp request_opts(reply, extra \\ []) do
    [
      api_key: "test-key",
      test_pid: self(),
      transport: Transport,
      transport_reply: reply
    ]
    |> Keyword.merge(extra)
  end

  defp ok(body), do: {:ok, 200, [], body}

  defp header(headers, wanted) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(name) == wanted, do: value
    end)
  end
end
