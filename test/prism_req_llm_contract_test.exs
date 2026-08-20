defmodule Spectre.Prism.ReqLLMContractTest.HTTPMock do
  @moduledoc false

  def run(request) do
    send(Process.get(:prism_req_llm_contract_pid), {
      :req_llm_http_request,
      request.method,
      URI.to_string(request.url),
      request.body
    })

    {request, Req.Response.new(status: 200, body: response_body(request.url))}
  end

  defp response_body(%URI{path: path}) when is_binary(path) do
    cond do
      String.ends_with?(path, "/responses") ->
        %{
          "id" => "resp_mock",
          "model" => "gpt-5.6-terra",
          "status" => "completed",
          "output" => [
            %{
              "type" => "message",
              "role" => "assistant",
              "content" => [%{"type" => "output_text", "text" => "openai mock"}]
            }
          ],
          "usage" => %{"input_tokens" => 2, "output_tokens" => 2, "total_tokens" => 4}
        }

      String.ends_with?(path, ":generateContent") ->
        %{
          "responseId" => "gemini_mock",
          "modelVersion" => "gemini-3.6-flash",
          "candidates" => [
            %{
              "finishReason" => "STOP",
              "content" => %{
                "role" => "model",
                "parts" => [%{"text" => "gemini mock"}]
              }
            }
          ],
          "usageMetadata" => %{
            "promptTokenCount" => 2,
            "candidatesTokenCount" => 2,
            "totalTokenCount" => 4
          }
        }

      String.ends_with?(path, ":embedContent") ->
        %{"embedding" => %{"values" => [0.25, 0.75]}}

      String.ends_with?(path, "/embeddings") ->
        %{
          "object" => "list",
          "data" => [
            %{"object" => "embedding", "index" => 0, "embedding" => [0.25, 0.75]}
          ],
          "usage" => %{"prompt_tokens" => 1, "total_tokens" => 1}
        }

      String.ends_with?(path, "/chat/completions") ->
        %{
          "id" => "chat_mock",
          "model" => "mock-model",
          "choices" => [
            %{
              "index" => 0,
              "finish_reason" => "stop",
              "message" => %{"role" => "assistant", "content" => "chat mock"}
            }
          ],
          "usage" => %{"prompt_tokens" => 2, "completion_tokens" => 2, "total_tokens" => 4}
        }
    end
  end
end

defmodule Spectre.Prism.ReqLLMContractTest do
  use ExUnit.Case, async: true

  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapters.Anthropic
  alias Spectre.Prism.Adapters.Cerebras
  alias Spectre.Prism.Adapters.DeepSeek
  alias Spectre.Prism.Adapters.Gemini
  alias Spectre.Prism.Adapters.Groq
  alias Spectre.Prism.Adapters.Mistral
  alias Spectre.Prism.Adapters.Ollama
  alias Spectre.Prism.Adapters.OpenAI
  alias Spectre.Prism.Adapters.OpenRouter
  alias Spectre.Prism.Adapters.XAI
  alias Spectre.Prism.ReqLLMContractTest.HTTPMock

  @generation_routes [
    {OpenAI, :openai, "/responses"},
    {Gemini, :google, "/models/gemini-3.6-flash:generateContent"},
    {OpenRouter, :openrouter, "/chat/completions"},
    {Ollama, :ollama, "/chat/completions"},
    {Anthropic, :anthropic, "/v1/messages"},
    {DeepSeek, :deepseek, "/chat/completions"},
    {Groq, :groq, "/chat/completions"},
    {XAI, :xai, "/chat/completions"},
    {Mistral, :mistral, "/chat/completions"},
    {Cerebras, :cerebras, "/chat/completions"}
  ]

  @embedding_routes [
    {OpenAI, :openai, "/embeddings"},
    {Gemini, :google, "/models/gemini-embedding-2:embedContent"},
    {OpenRouter, :openrouter, "/embeddings"},
    {Ollama, :ollama, "/embeddings"},
    {Mistral, :mistral, "/embeddings"}
  ]

  setup do
    Process.put(:prism_req_llm_contract_pid, self())
    on_exit(fn -> Process.delete(:prism_req_llm_contract_pid) end)
    :ok
  end

  test "every bundled provider resolves to a real ReqLLM request builder" do
    for {adapter, req_provider, expected_path} <- @generation_routes do
      catalog = adapter.catalog()
      profile = Keyword.fetch!(catalog.profiles, :balanced)
      model = Keyword.fetch!(profile, :model)

      assert catalog.options[:req_llm_provider] == req_provider
      assert {:ok, provider_module} = ReqLLM.provider(req_provider)

      assert {:ok, %Req.Request{method: :post} = request} =
               provider_module.prepare_request(
                 :chat,
                 %{provider: req_provider, id: model},
                 "contract probe",
                 api_key: "mock-key"
               )

      assert URI.to_string(request.url) == expected_path
    end
  end

  test "all bundled embedding providers resolve to ReqLLM embedding endpoints" do
    for {adapter, req_provider, expected_path} <- @embedding_routes do
      catalog = adapter.catalog()
      model = Keyword.fetch!(catalog.embedding, :model)
      dimensions = Keyword.get(catalog.embedding, :dimensions, 8)

      assert {:ok, provider_module} = ReqLLM.provider(req_provider)

      assert {:ok, %Req.Request{method: :post} = request} =
               provider_module.prepare_request(
                 :embedding,
                 %{provider: req_provider, id: model},
                 "contract probe",
                 api_key: "mock-key",
                 dimensions: dimensions
               )

      assert URI.to_string(request.url) == expected_path
    end
  end

  test "OpenAI, Gemini, OpenRouter, and Ollama complete through mocked ReqLLM HTTP" do
    cases = [
      {OpenAI, "openai mock", "https://api.openai.com/v1/responses"},
      {Gemini, "gemini mock",
       "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"},
      {OpenRouter, "chat mock", "https://openrouter.ai/api/v1/chat/completions"},
      {Ollama, "chat mock", "http://127.0.0.1:11434/v1/chat/completions"}
    ]

    for {adapter, expected_text, expected_url} <- cases do
      assert {:ok, %Response{text: ^expected_text}} = adapter.complete("hello", http_options())
      assert_receive {:req_llm_http_request, :post, actual_url, encoded_body}
      assert actual_url |> URI.parse() |> Map.put(:query, nil) |> URI.to_string() == expected_url

      assert {:ok, body} = encoded_body |> IO.iodata_to_binary() |> Jason.decode()
      assert body["model"] || body["contents"]
    end
  end

  test "OpenAI, Gemini, OpenRouter, and Ollama embed through mocked ReqLLM HTTP" do
    cases = [
      {OpenAI, "https://api.openai.com/v1/embeddings"},
      {Gemini,
       "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-2:embedContent"},
      {OpenRouter, "https://openrouter.ai/api/v1/embeddings"},
      {Ollama, "http://127.0.0.1:11434/v1/embeddings"}
    ]

    for {adapter, expected_url} <- cases do
      assert {:ok, [0.25, 0.75]} = adapter.embed("hello", http_options())
      assert_receive {:req_llm_http_request, :post, actual_url, encoded_body}
      assert actual_url |> URI.parse() |> Map.put(:query, nil) |> URI.to_string() == expected_url
      assert encoded_body |> IO.iodata_to_binary() |> Jason.decode!() |> is_map()
    end
  end

  defp http_options do
    [api_key: "mock-key", req_http_options: [adapter: HTTPMock]]
  end
end
