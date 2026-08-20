defmodule Spectre.Prism.AdaptersTest.ReqLLMMock do
  @moduledoc false

  def generate_text(model, prompt, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:generate_text, model, prompt, opts})

    {:ok,
     %{
       id: "mock-request",
       model: model.id,
       text: Keyword.get(opts, :mock_text, "mock completion"),
       usage: %{input_tokens: 3, output_tokens: 2, total_tokens: 5},
       finish_reason: :stop
     }}
  end

  def embed(model, input, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:embed, model, input, opts})

    vectors =
      case input do
        inputs when is_list(inputs) -> Enum.map(inputs, fn _input -> [0.25, 0.75] end)
        _input -> [0.25, 0.75]
      end

    {:ok, vectors}
  end
end

defmodule Spectre.Prism.AdaptersTest do
  use ExUnit.Case, async: true

  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapters.Gemini
  alias Spectre.Prism.Adapters.Ollama
  alias Spectre.Prism.Adapters.OpenAI
  alias Spectre.Prism.Adapters.OpenRouter
  alias Spectre.Prism.AdaptersTest.ReqLLMMock
  alias Spectre.Prism.Registry
  alias Spectre.Prompt.Plan
  alias Spectre.Router.LLMClassifier

  @adapters [
    {OpenAI, :openai, "gpt-5.6-terra", :openai},
    {Gemini, :google, "gemini-3.6-flash", :gemini},
    {OpenRouter, :openrouter, "openai/gpt-5.6-terra", :openrouter},
    {Ollama, :ollama, "qwen3.5:9b", :ollama}
  ]

  @embeddings [
    {OpenAI, :openai, "text-embedding-3-small", 1536},
    {Gemini, :google, "gemini-embedding-2", 768},
    {OpenRouter, :openrouter, "openai/text-embedding-3-small", 1536},
    {Ollama, :ollama, "embeddinggemma", 768}
  ]

  test "all primary adapters delegate generation to the expected ReqLLM provider" do
    for {adapter, req_provider, model, prism_provider} <- @adapters do
      assert {:ok,
              %Response{
                text: "mock completion",
                provider_request_id: "mock-request",
                usage: %{total_tokens: 5},
                metadata: %{provider: ^prism_provider, model: ^model}
              }} = adapter.complete("hello", mock_options())

      assert_receive {:generate_text, %{provider: ^req_provider, id: ^model}, "hello", opts}
      assert opts[:test_pid] == self()
      refute Keyword.has_key?(opts, :req_llm_module)
      refute Keyword.has_key?(opts, :req_llm_provider)
      assert is_binary(opts[:base_url])
    end
  end

  test "primary adapters delegate single and batch embeddings to ReqLLM" do
    for {adapter, req_provider, model, dimensions} <- @embeddings do
      assert {:ok, [0.25, 0.75]} = adapter.embed("one", mock_options())
      assert_receive {:embed, %{provider: ^req_provider, id: ^model}, "one", _opts}

      assert {:ok, [[0.25, 0.75], [0.25, 0.75]]} =
               adapter.embed(["one", "two"], mock_options())

      assert_receive {:embed, %{provider: ^req_provider, id: ^model}, ["one", "two"], _opts}
      assert {:ok, ^dimensions} = adapter.load(model)
      assert {:ok, ^dimensions} = adapter.download(model)
    end
  end

  test "prompt plans become a ReqLLM prompt plus system_prompt" do
    plan = %Plan{
      instructions: [%{content: "follow policy"}],
      context: [%{content: "<untrusted & data>"}],
      task: [%{content: "answer"}]
    }

    assert {:ok, %Response{text: "mock completion"}} =
             Gemini.complete_plan(plan, mock_options())

    assert_receive {:generate_text, %{provider: :google}, prompt, opts}
    assert opts[:system_prompt] == "follow policy"
    assert prompt =~ "&lt;untrusted &amp; data&gt;"
    assert prompt =~ "answer"
  end

  test "canonical ReqLLM options and provider options pass through unchanged" do
    assert {:ok, %Response{}} =
             Gemini.complete(
               "hello",
               mock_options(
                 max_output_tokens: 64,
                 reasoning_effort: :high,
                 provider_options: [google_grounding: %{enable: true}]
               )
             )

    assert_receive {:generate_text, %{provider: :google}, "hello", opts}
    assert opts[:max_tokens] == 64
    assert opts[:reasoning_effort] == :high
    assert opts[:provider_options] == [google_grounding: %{enable: true}]
    refute Keyword.has_key?(opts, :max_output_tokens)
  end

  test "custom model, base URL, and ReqLLM provider overrides remain available" do
    assert {:ok, %Response{metadata: %{provider: :gemini, model: "custom-model"}}} =
             Gemini.complete(
               "hello",
               mock_options(
                 model: "custom-model",
                 req_llm_provider: :google_vertex,
                 base_url: "https://proxy.example/v1"
               )
             )

    assert_receive {:generate_text,
                    %{
                      provider: :google_vertex,
                      id: "custom-model",
                      base_url: "https://proxy.example/v1"
                    }, "hello", _opts}
  end

  test "registry-provided ReqLLM model runs through Spectre's classifier boundary" do
    assert {:ok, registry} =
             Registry.build([
               {:openai, OpenAI, [embedding: false, req_llm_module: ReqLLMMock]}
             ])

    opts = [
      classifier: Registry.classifier(registry),
      test_pid: self(),
      mock_text: "GREETING"
    ]

    assert {:ok, route} = LLMClassifier.classify("ciao", [:GREETING, :OTHER], opts)
    assert route.label == :GREETING
    assert route.strategy == :llm_classifier

    assert_receive {:generate_text, %{provider: :openai, id: "gpt-5.6-luna"}, prompt, req_opts}
    assert prompt =~ "Available labels:"
    assert req_opts[:max_tokens] == 8
  end

  defp mock_options(extra \\ []) do
    [req_llm_module: ReqLLMMock, test_pid: self()]
    |> Keyword.merge(extra)
  end
end
