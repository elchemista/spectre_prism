defmodule Spectre.Prism.AdapterBoundariesTest.Transport do
  @moduledoc false

  @behaviour Spectre.Prism.Adapter.Transport

  @impl true
  def request(method, url, headers, body, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:boundary_request, method, url, headers, body})
    Keyword.fetch!(opts, :transport_reply)
  end
end

defmodule Spectre.Prism.AdapterBoundariesTest do
  use ExUnit.Case, async: true

  alias Spectre.Inference.Response
  alias Spectre.Prism.Adapter.Error
  alias Spectre.Prism.AdapterBoundariesTest.Transport
  alias Spectre.Prism.Adapters
  alias Spectre.Prism.Adapters.Gemini
  alias Spectre.Prism.Adapters.Ollama
  alias Spectre.Prism.Adapters.OpenAI
  alias Spectre.Prism.Adapters.OpenRouter
  alias Spectre.Prompt.Plan

  @adapters [
    openai: OpenAI,
    openrouter: OpenRouter,
    ollama: Ollama,
    gemini: Gemini
  ]

  test "public adapter boundaries reject malformed prompts, models, options, and URLs" do
    for {provider, adapter} <- @adapters do
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

      assert_error(adapter.load("", []), provider, :configuration, :invalid_model)

      assert_error(
        adapter.load("custom-model", dimensions: 0),
        provider,
        :configuration,
        :invalid_embedding_dimensions
      )

      assert_error(
        adapter.embed("", []),
        provider,
        :configuration,
        :invalid_embedding_input
      )

      assert_error(
        adapter.complete(
          "hello",
          runtime_opts(ok(%{"output_text" => "unused"}), base_url: :invalid)
        ),
        provider,
        :configuration,
        :invalid_url
      )
    end

    assert_error(Ollama.download("", []), :ollama, :configuration, :invalid_model)
    assert_error(OpenAI.embed([], []), :openai, :configuration, :invalid_embedding_input)

    assert_error(
      OpenRouter.embed(["ok", ""], []),
      :openrouter,
      :configuration,
      :invalid_embedding_input
    )

    assert_error(Gemini.embed(:invalid, []), :gemini, :configuration, :invalid_embedding_input)
  end

  test "malformed provider responses never escape adapter contracts" do
    assert_error(
      OpenRouter.complete("hello", runtime_opts(ok(%{"choices" => %{}}))),
      :openrouter,
      :invalid_response,
      :missing_output_text
    )

    assert {:ok, %Response{usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}}} =
             Ollama.complete(
               "hello",
               runtime_opts(
                 ok(%{
                   "message" => %{"content" => "local"},
                   "prompt_eval_count" => "secret",
                   "eval_count" => nil
                 }),
                 api_key: nil
               )
             )

    assert {:ok, %Response{usage: %{input_tokens: 2, output_tokens: 0, total_tokens: 2}}} =
             OpenAI.complete(
               "hello",
               runtime_opts(
                 ok(%{
                   "output_text" => "safe",
                   "usage" => %{"input_tokens" => 2, "output_tokens" => -1, "total_tokens" => "5"}
                 })
               )
             )

    assert_error(
      Ollama.embed("hello", runtime_opts(ok(%{"embeddings" => [[1, :invalid]]}), api_key: nil)),
      :ollama,
      :invalid_response,
      :invalid_embedding_vector
    )

    assert_error(
      Gemini.embed("hello", runtime_opts(ok(%{"embedding" => %{"values" => []}}))),
      :gemini,
      :invalid_response,
      :invalid_embedding_vector
    )
  end

  test "alternate response shapes and typed prompt plans are normalized" do
    plan = %Plan{
      instructions: [%{content: "follow policy"}],
      context: [%{content: "<untrusted & data>"}],
      task: [%{content: "answer"}]
    }

    assert {:ok, %Response{text: "part onepart two"}} =
             OpenRouter.complete_plan(
               plan,
               runtime_opts(
                 ok(%{
                   "choices" => [
                     %{
                       "message" => %{
                         "content" => [
                           %{"type" => "text", "text" => "part one"},
                           %{"text" => "part two"}
                         ]
                       }
                     }
                   ]
                 })
               )
             )

    assert_receive {:boundary_request, :post, _url, _headers, body}
    assert Enum.at(body["messages"], 0) == %{"role" => "system", "content" => "follow policy"}
    assert Enum.at(body["messages"], 1)["content"] =~ "&lt;untrusted &amp; data&gt;"

    assert {:ok, %Response{text: "direct"}} =
             Gemini.complete(
               "hello",
               runtime_opts(ok(%{"output_text" => "direct", "usage" => :invalid}),
                 interaction_api_version: "v1beta/preview"
               )
             )

    assert_receive {:boundary_request, :post, gemini_url, _headers, _body}
    assert gemini_url =~ "/v1beta%2Fpreview/interactions"

    assert {:ok, [0.25, 0.5]} =
             Gemini.embed(
               "hello",
               runtime_opts(ok(%{"embeddings" => [%{"values" => [0.25, 0.5]}]}),
                 model: "models/custom/name",
                 task_type: "retrieval_query"
               )
             )

    assert_receive {:boundary_request, :post, embedding_url, _headers, embedding_body}
    assert embedding_url =~ "/models/custom%2Fname:embedContent"
    assert embedding_body["embedContentConfig"]["taskType"] == "retrieval_query"
  end

  test "embedding batches require exact unique provider indexes" do
    duplicate =
      ok(%{
        "data" => [
          %{"index" => 0, "embedding" => [1]},
          %{"index" => 0, "embedding" => [2]}
        ]
      })

    assert_error(
      OpenAI.embed(["one", "two"], runtime_opts(duplicate)),
      :openai,
      :invalid_response,
      :invalid_embedding_index
    )

    assert_error(
      OpenRouter.embed(
        "one",
        runtime_opts(ok(%{"data" => [%{"index" => -1, "embedding" => [1]}]}))
      ),
      :openrouter,
      :invalid_response,
      :invalid_embedding_index
    )

    assert_error(
      OpenAI.embed("one", runtime_opts(ok(%{"error" => %{"code" => "embedding_failed"}}))),
      :openai,
      :provider,
      "embedding_failed"
    )

    assert_error(
      OpenRouter.embed("one", runtime_opts(ok([]))),
      :openrouter,
      :invalid_response,
      :embedding_response_not_an_object
    )

    assert_error(
      OpenAI.embed(
        ["one", "two"],
        runtime_opts(
          ok(%{
            "data" => [
              %{"index" => 0, "embedding" => [1]},
              %{"index" => 1, "embedding" => [1, 2]}
            ]
          })
        )
      ),
      :openai,
      :invalid_response,
      :embedding_dimensions_mismatch
    )
  end

  test "unknown embedding dimensions are probed through each provider" do
    assert {:ok, 2} =
             OpenAI.load(
               "custom-openai",
               runtime_opts(ok(%{"data" => [%{"embedding" => [1, 2]}]}))
             )

    assert {:ok, 2} =
             OpenRouter.load(
               "custom-openrouter",
               runtime_opts(ok(%{"data" => [%{"embedding" => [1, 2]}]}))
             )

    assert {:ok, 2} =
             Ollama.load(
               "custom-ollama",
               runtime_opts(ok(%{"embeddings" => [[1, 2]]}), api_key: nil)
             )

    assert {:ok, 2} =
             Gemini.load(
               "custom-gemini",
               runtime_opts(ok(%{"embedding" => %{"values" => [1, 2]}}))
             )
  end

  test "provider-declared errors are reduced to stable codes" do
    for {provider, adapter} <- @adapters do
      opts = runtime_opts(ok(%{"error" => %{"type" => "provider_error"}}))
      result = adapter.complete("hello", opts)
      assert_error(result, provider, :provider, "provider_error")
    end
  end

  test "all remaining response variants return typed values or typed errors" do
    assert Adapters.built_ins() == [OpenAI, OpenRouter, Ollama, Gemini]

    for {provider, adapter} <- @adapters do
      assert_error(
        adapter.complete("hello", runtime_opts(ok([]))),
        provider,
        :invalid_response,
        :response_not_an_object
      )
    end

    assert {:ok, %Response{text: "fallback"}} =
             OpenAI.complete(
               "hello",
               runtime_opts(
                 ok(%{
                   "output" => [%{"content" => [%{"text" => "fallback"}, %{"ignored" => true}]}],
                   "usage" => :invalid
                 })
               )
             )

    assert_error(
      OpenAI.complete("hello", runtime_opts(ok(%{"output" => :invalid}))),
      :openai,
      :invalid_response,
      :missing_output_text
    )

    assert_error(
      OpenRouter.complete(
        "hello",
        runtime_opts(
          ok(%{"choices" => [%{"message" => %{"content" => []}}], "usage" => :invalid})
        )
      ),
      :openrouter,
      :invalid_response,
      :missing_output_text
    )

    assert_error(
      Ollama.complete("hello", runtime_opts(ok(%{}), api_key: nil)),
      :ollama,
      :invalid_response,
      :missing_output_text
    )

    assert_error(
      Ollama.embed("hello", runtime_opts(ok(%{}), api_key: nil)),
      :ollama,
      :invalid_response,
      :missing_embedding_vector
    )

    assert_error(
      Ollama.embed(
        "hello",
        runtime_opts(ok(%{"error" => %{"code" => "embed_failed"}}), api_key: nil)
      ),
      :ollama,
      :provider,
      "embed_failed"
    )

    assert_error(
      Ollama.embed("hello", runtime_opts(ok([]), api_key: nil)),
      :ollama,
      :invalid_response,
      :embedding_response_not_an_object
    )

    assert {:ok, %Response{text: "last model output"}} =
             Gemini.complete(
               "hello",
               runtime_opts(
                 ok(%{
                   "steps" => [
                     %{"type" => "ignored"},
                     %{
                       "type" => "model_output",
                       "content" => [%{"text" => "last model output"}, %{"ignored" => true}]
                     }
                   ]
                 }),
                 generation_config: :invalid,
                 api_revision: "2026-08",
                 task_type: %{custom: true}
               )
             )

    assert_error(
      Gemini.complete("hello", runtime_opts(ok(%{"steps" => :invalid}), api_revision: :invalid)),
      :gemini,
      :invalid_response,
      :missing_output_text
    )

    assert_error(
      Gemini.embed("hello", runtime_opts(ok(%{}))),
      :gemini,
      :invalid_response,
      :missing_embedding_vector
    )

    assert_error(
      Gemini.embed("hello", runtime_opts(ok(%{"error" => %{"code" => "embed_failed"}}))),
      :gemini,
      :provider,
      "embed_failed"
    )

    assert_error(
      Gemini.embed("hello", runtime_opts(ok([]))),
      :gemini,
      :invalid_response,
      :embedding_response_not_an_object
    )

    assert_error(
      Gemini.embed("hello", runtime_opts(ok(%{}), embedding_api_version: :invalid)),
      :gemini,
      :configuration,
      :invalid_api_version
    )

    assert_error(
      Gemini.embed("hello", runtime_opts(ok(%{}), model: "models/")),
      :gemini,
      :configuration,
      :invalid_model
    )
  end

  test "provider request options are translated without unsafe implicit values" do
    assert {:ok, %Response{text: "configured"}} =
             OpenAI.complete(
               "hello",
               runtime_opts(ok(%{"output_text" => "configured"}),
                 max_tokens: 12,
                 reasoning_effort: :high,
                 temperature: 0.2,
                 top_p: 0.9,
                 text: [format: :json],
                 store: false,
                 service_tier: :priority
               )
             )

    assert_receive {:boundary_request, :post, _url, _headers, body}
    assert body["max_output_tokens"] == 12
    assert body["reasoning"] == %{"effort" => "high"}
    assert body["text"] == %{"format" => "json"}
    assert body["store"] == false

    assert {:ok, %Response{text: "explicit reasoning"}} =
             OpenAI.complete(
               "hello",
               runtime_opts(ok(%{"output_text" => "explicit reasoning"}),
                 reasoning: [effort: :low],
                 reasoning_effort: :high
               )
             )

    assert_receive {:boundary_request, :post, _url, _headers, explicit_body}
    assert explicit_body["reasoning"] == %{"effort" => "low"}

    assert_error(
      OpenAI.complete(
        "hello",
        runtime_opts(ok(%{"output_text" => "unused"}),
          reasoning: %{{:tuple, :key} => :high},
          transport: String
        )
      ),
      :openai,
      :configuration,
      :transport_unavailable
    )

    assert {:ok, %Response{text: "router"}} =
             OpenRouter.complete(
               "hello",
               runtime_opts(ok(%{"choices" => [%{"message" => %{"content" => "router"}}]}),
                 site_url: :invalid,
                 app_name: :invalid
               )
             )

    assert {:ok, %Response{text: "ollama"}} =
             Ollama.complete(
               "hello",
               runtime_opts(ok(%{"message" => %{"content" => "ollama"}}),
                 options: :invalid,
                 api_key: "runtime-key"
               )
             )
  end

  defp runtime_opts(reply, extra \\ []) do
    [
      api_key: "test-key",
      test_pid: self(),
      transport: Transport,
      transport_reply: reply
    ]
    |> Keyword.merge(extra)
  end

  defp ok(body), do: {:ok, 200, [], body}

  defp assert_error(result, provider, kind, code) do
    assert {:error, %Error{provider: ^provider, kind: ^kind, code: ^code}} = result
  end
end
