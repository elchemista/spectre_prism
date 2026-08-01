defmodule Spectre.Prism.RegistryTest.CustomAdapter do
  @moduledoc false

  alias Spectre.Prompt.Plan

  @behaviour Spectre.Prism.Adapter
  @behaviour Spectre.LLM

  @impl Spectre.Prism.Adapter
  def catalog do
    %{
      profiles: [specialist: [model: "custom-v1", rank: 25]],
      classifier: :specialist
    }
  end

  @impl Spectre.LLM
  def complete(prompt, _opts), do: {:ok, prompt}

  @impl Spectre.LLM
  def complete_plan(plan, _opts), do: {:ok, Plan.legacy(plan)}
end

defmodule Spectre.Prism.RegistryTest.Stack do
  @moduledoc false

  use Spectre.Stack, id: :prism_provider_registry

  install Spectre.Prism do
    provider(:ollama, Spectre.Prism.Adapters.Ollama)
  end
end

defmodule Spectre.Prism.RegistryTest.StackAgent do
  @moduledoc false

  use Spectre.Agent, stack: Spectre.Prism.RegistryTest.Stack
  router(via: [:regex], semantic_cache?: false, classification_log?: false)
end

defmodule Spectre.Prism.RegistryTest.LocalAgent do
  @moduledoc false

  use Spectre.Agent
  use Spectre.Prism

  prism do
    provider(
      :openai,
      Spectre.Prism.Adapters.OpenAI,
      classifier: false,
      embedding: false,
      base_url: "https://gateway.example/v1"
    )
  end
end

defmodule Spectre.Prism.RegistryTest do
  use ExUnit.Case, async: true

  alias Spectre.Prism.Adapters.Gemini
  alias Spectre.Prism.Adapters.Ollama
  alias Spectre.Prism.Adapters.OpenAI
  alias Spectre.Prism.Adapters.OpenRouter
  alias Spectre.Prism.Registry
  alias Spectre.Prism.RegistryTest.CustomAdapter
  alias Spectre.Prism.RegistryTest.LocalAgent
  alias Spectre.Prism.RegistryTest.Stack
  alias Spectre.Prism.RegistryTest.StackAgent
  alias Spectre.Stack.Definition

  @built_ins [
    openai: {OpenAI, ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol"]},
    openrouter:
      {OpenRouter, ["openai/gpt-5.6-luna", "openai/gpt-5.6-terra", "openai/gpt-5.6-sol"]},
    ollama: {Ollama, ["qwen3.5:0.8b", "qwen3.5:9b", "qwen3.5:35b"]},
    gemini: {Gemini, ["gemini-3.5-flash-lite", "gemini-3.6-flash", "gemini-3.5-flash"]}
  ]

  test "provider modules compile fast, balanced, and deep Spectre intelligence levels" do
    for {id, {adapter, models}} <- @built_ins do
      assert {:ok, registry} = Registry.build([{id, adapter}])
      assert Enum.map(Registry.profiles(registry), &elem(&1, 0)) == [:fast, :balanced, :deep]

      compiled_models =
        Enum.map(Registry.profiles(registry), fn {level, opts} ->
          assert {^adapter, :complete_plan, adapter_opts} = Keyword.fetch!(opts, :model)
          assert opts[:metadata].prism_provider == id
          assert level in [:fast, :balanced, :deep]
          Keyword.fetch!(adapter_opts, :model)
        end)

      assert compiled_models == models
      assert [route_classification: [prefer: :fast]] = Registry.purpose_defaults(registry)

      classifier = Registry.classifier(registry)
      assert {^adapter, :complete_plan, classifier_opts} = Keyword.fetch!(classifier, :adapter)

      assert Keyword.fetch!(classifier_opts, :model) == hd(models)
      assert {^adapter, embedding_opts} = Registry.embedding(registry)
      assert is_binary(Keyword.fetch!(embedding_opts, :model))
    end
  end

  test "optional provider parameters override models without changing intelligence identifiers" do
    assert {:ok, registry} =
             Registry.build([
               {:openai, OpenAI,
                [
                  models: [
                    fast: "acme/cheap",
                    deep: [model: "acme/reasoning", rank: 40]
                  ],
                  classifier: :fast,
                  embedding: [model: "text-embedding-3-large", dimensions: 3072],
                  base_url: "https://gateway.example/v1"
                ]}
             ])

    assert [fast: fast, balanced: _balanced, deep: deep] = Registry.profiles(registry)
    assert {OpenAI, :complete_plan, fast_opts} = fast[:model]
    assert fast_opts[:model] == "acme/cheap"
    assert fast_opts[:base_url] == "https://gateway.example/v1"
    assert deep[:rank] == 40
    assert registry.classifier_profile == :fast
    assert {OpenAI, embedding_opts} = registry.embedding
    assert embedding_opts[:model] == "text-embedding-3-large"
    assert embedding_opts[:dimensions] == 3072

    assert {:ok, custom} = Registry.build([{:custom, CustomAdapter}])
    assert [{:specialist, opts}] = Registry.profiles(custom)
    assert {CustomAdapter, :complete_plan, model: "custom-v1"} = opts[:model]
    assert custom.embedding == nil
  end

  test "the adapter module is explicit and catalog providers keep plain level identifiers" do
    assert {:error, {:invalid_prism_provider_adapter, :openai, []}} =
             Registry.build([{:openai, []}])

    assert {:error, {:missing_prism_provider_catalog, String}} =
             Registry.build([{:custom, String}])

    assert {:error, {:duplicate_prism_provider_profile, :fast}} =
             Registry.build([{:openai, OpenAI}, {:ollama, Ollama}])

    assert {:ok, registry} = Registry.build([{:openroute, OpenRouter}])
    assert [{:fast, opts} | _rest] = Registry.profiles(registry)
    assert {OpenRouter, :complete_plan, _adapter_opts} = opts[:model]
  end

  test "credentials stay runtime-owned" do
    assert {:error, {:prism_provider_secret_must_be_runtime, :api_key}} =
             Registry.build([{:openai, OpenAI, [api_key: "must-not-be-compiled"]}])

    assert {:error, {:prism_provider_secret_must_be_runtime, "Authorization"}} =
             Registry.build([
               {:openai, OpenAI, [headers: [{"Authorization", "Bearer secret"}]]}
             ])
  end

  test "Stack and Agent-local provider declarations contribute classifier and embedding defaults" do
    assert {:ok, installation} = Definition.installation(Stack, :prism)
    assert installation.config.providers == [ollama: Ollama]
    refute Map.has_key?(installation.config, :intelligences)

    assert {:ok, stack_config} = Spectre.Prism.config(StackAgent)
    assert Enum.map(stack_config.profiles, & &1.id) == [:fast, :balanced, :deep]
    assert {Ollama, _embedding_opts} = stack_config.embedding

    definition_config = StackAgent.__spectre_definition__().config
    assert definition_config[:classifier] == stack_config.classifier
    assert definition_config[:embedding] == stack_config.embedding

    assert {:ok, local_config} = Spectre.Prism.config(LocalAgent)
    assert Enum.map(local_config.profiles, & &1.id) == [:fast, :balanced, :deep]
    assert local_config.classifier == nil
    assert local_config.embedding == nil

    assert [registration] = local_config.registry.registrations
    assert registration.id == :openai
    assert registration.adapter == OpenAI
    assert registration.options[:base_url] == "https://gateway.example/v1"
  end
end
