defmodule Spectre.Prism.AdapterBoundariesTest.RaisingClient do
  @moduledoc false
  def generate_text(_model, _prompt, _opts), do: raise("private upstream failure")
  def embed(_model, _input, _opts), do: exit(:private_upstream_exit)
end

defmodule Spectre.Prism.AdapterBoundariesTest.InvalidClient do
  @moduledoc false
  def generate_text(_model, _prompt, _opts), do: {:ok, %{text: ""}}
  def embed(_model, _input, _opts), do: {:ok, []}
end

defmodule Spectre.Prism.AdapterBoundariesTest.ProbeClient do
  @moduledoc false
  def generate_text(_model, _prompt, _opts), do: {:ok, "ok"}
  def embed(_model, _input, _opts), do: {:ok, [1, 2, 3, 4]}
end

defmodule Spectre.Prism.AdapterBoundariesTest.ResultClient do
  @moduledoc false
  def generate_text(_model, _prompt, opts), do: Keyword.fetch!(opts, :result)
  def embed(_model, _input, opts), do: Keyword.fetch!(opts, :result)
end

defmodule Spectre.Prism.AdapterBoundariesTest do
  use ExUnit.Case, async: true

  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.AdapterBoundariesTest.InvalidClient
  alias Spectre.Prism.AdapterBoundariesTest.ProbeClient
  alias Spectre.Prism.AdapterBoundariesTest.RaisingClient
  alias Spectre.Prism.AdapterBoundariesTest.ResultClient
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
  alias Spectre.Prompt.Plan

  @generation_adapters [
    openai: OpenAI,
    gemini: Gemini,
    openrouter: OpenRouter,
    ollama: Ollama,
    anthropic: Anthropic,
    deepseek: DeepSeek,
    groq: Groq,
    xai: XAI,
    mistral: Mistral,
    cerebras: Cerebras
  ]

  @embedding_adapters [
    openai: OpenAI,
    gemini: Gemini,
    openrouter: OpenRouter,
    ollama: Ollama,
    mistral: Mistral
  ]

  test "ReqLLM-backed adapters reject malformed public inputs with typed errors" do
    for {provider, adapter} <- @generation_adapters do
      assert_error(adapter.complete(:invalid, []), provider, :configuration, :invalid_prompt)

      assert_error(
        adapter.complete("hello", [:not_a_keyword]),
        provider,
        :configuration,
        :invalid_options
      )

      assert_error(
        adapter.complete_plan(:invalid, []),
        provider,
        :configuration,
        :invalid_prompt_plan
      )

      assert_error(
        adapter.complete_plan(%Plan{instructions: :invalid}, []),
        provider,
        :configuration,
        :invalid_prompt_plan
      )

      assert_error(
        adapter.complete("hello", base_url: :invalid),
        provider,
        :configuration,
        :invalid_base_url
      )

      assert_error(
        adapter.complete("hello", req_llm_provider: "invalid"),
        provider,
        :configuration,
        :invalid_req_llm_provider
      )
    end

    for {provider, adapter} <- @embedding_adapters do
      assert_error(adapter.load("", []), provider, :configuration, :invalid_model)

      assert_error(
        adapter.load("model", dimensions: 0),
        provider,
        :configuration,
        :invalid_embedding_dimensions
      )

      assert_error(adapter.embed("", []), provider, :configuration, :invalid_embedding_input)
      assert_error(adapter.embed([], []), provider, :configuration, :invalid_embedding_input)

      assert_error(
        adapter.embed(["ok", ""], []),
        provider,
        :configuration,
        :invalid_embedding_input
      )
    end
  end

  test "client exceptions, exits, and malformed results never escape the adapter contract" do
    assert_error(
      OpenAI.complete("private prompt", req_llm_module: RaisingClient),
      :openai,
      :transport,
      :req_llm_exception
    )

    assert_error(
      Gemini.embed("private input", req_llm_module: RaisingClient),
      :gemini,
      :transport,
      :req_llm_exit
    )

    assert_error(
      OpenRouter.complete("hello", req_llm_module: InvalidClient),
      :openrouter,
      :invalid_response,
      :missing_output_text
    )

    assert_error(
      Ollama.embed("hello", req_llm_module: InvalidClient),
      :ollama,
      :invalid_response,
      :invalid_embedding_vector
    )
  end

  test "unknown embedding dimensions are probed through ReqLLM" do
    assert {:ok, 4} =
             OpenAI.load("custom-embedding",
               req_llm_module: ProbeClient
             )

    assert {:ok, 4} =
             Gemini.load("custom-embedding",
               req_llm_module: ProbeClient
             )
  end

  test "invalid client modules and model metadata are rejected before an API call" do
    assert_error(
      OpenAI.complete("hello", req_llm_module: String),
      :openai,
      :configuration,
      :req_llm_unavailable
    )

    assert_error(
      Gemini.complete("hello", model_extra: :invalid),
      :gemini,
      :configuration,
      :invalid_model_extra
    )

    assert_error(
      OpenRouter.complete("hello", model: ""),
      :openrouter,
      :configuration,
      :invalid_model
    )

    assert_error(
      OpenAI.complete("hello", api_key: ""),
      :openai,
      :configuration,
      :invalid_api_key
    )

    assert_error(
      Gemini.complete("hello", base_url: ""),
      :gemini,
      :configuration,
      :invalid_base_url
    )
  end

  test "ReqLLM result variants are normalized without leaking upstream details" do
    assert {:ok, %{text: "plain text"}} =
             OpenAI.complete("hello", req_llm_module: ResultClient, result: {:ok, "plain text"})

    assert {:ok, [[1.0, 2.0], [3.0, 4.0]]} =
             OpenAI.embed(["one", "two"],
               req_llm_module: ResultClient,
               result: {:ok, [[1, 2], [3, 4]]}
             )

    assert_error(
      OpenAI.complete("hello", req_llm_module: ResultClient, result: {:ok, :invalid}),
      :openai,
      :invalid_response,
      :invalid_req_llm_response
    )

    timeout = ReqLLM.Error.API.Timeout.exception(kind: :total, timeout: 1_000)

    assert_error(
      Gemini.complete("hello", req_llm_module: ResultClient, result: {:error, timeout}),
      :gemini,
      :transport,
      :timeout
    )

    response_error = ReqLLM.Error.API.Response.exception(reason: "private response")

    assert_error(
      OpenRouter.complete("hello",
        req_llm_module: ResultClient,
        result: {:error, response_error}
      ),
      :openrouter,
      :invalid_response,
      :req_llm_response_error
    )
  end

  defp assert_error(result, provider, kind, code) do
    assert {:error, %Error{provider: ^provider, kind: ^kind, code: ^code}} = result
  end
end
