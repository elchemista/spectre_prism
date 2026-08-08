defmodule Spectre.Prism.RegistryHardeningTest.Adapters do
  @moduledoc false

  defmodule NoCapabilities do
    @behaviour Spectre.Prism.Adapter
    @behaviour Spectre.LLM

    @impl true
    def catalog, do: %{profiles: [specialist: [model: "specialist", rank: 40]]}

    @impl true
    def complete(_prompt, _opts), do: {:ok, "ok"}

    @impl true
    def complete_plan(_plan, _opts), do: {:ok, "ok"}
  end

  defmodule OtherCapabilities do
    @behaviour Spectre.Prism.Adapter
    @behaviour Spectre.LLM
    @behaviour Spectre.Classifier.Embedding

    @impl true
    def catalog do
      %{
        profiles: [specialist: [model: "specialist", rank: 40]],
        classifier: :specialist,
        embedding: [model: "specialist-embedding", dimensions: 2]
      }
    end

    @impl true
    def complete(_prompt, _opts), do: {:ok, "ok"}

    @impl true
    def complete_plan(_plan, _opts), do: {:ok, "ok"}

    @impl true
    def load(_model, _opts), do: {:ok, 2}

    @impl true
    def download(_model, _opts), do: {:ok, 2}

    @impl true
    def embed(_text, _opts), do: {:ok, [0.0, 1.0]}
  end

  defmodule ExplicitEmbedding do
    @behaviour Spectre.Prism.Adapter
    @behaviour Spectre.LLM
    @behaviour Spectre.Classifier.Embedding

    @impl true
    def catalog, do: %{profiles: [specialist: [model: "specialist", rank: 40]]}

    @impl true
    def complete(_prompt, _opts), do: {:ok, "ok"}

    @impl true
    def complete_plan(_plan, _opts), do: {:ok, "ok"}

    @impl true
    def load(_model, _opts), do: {:ok, 2}

    @impl true
    def download(_model, _opts), do: {:ok, 2}

    @impl true
    def embed(_text, _opts), do: {:ok, [0.0, 1.0]}
  end

  defmodule SecretCatalog do
    @behaviour Spectre.Prism.Adapter
    @behaviour Spectre.LLM

    @impl true
    def catalog do
      %{
        options: [headers: [{"X-Api-Key", "compiled-secret"}]],
        profiles: [secret: [model: "secret", rank: 40]]
      }
    end

    @impl true
    def complete(_prompt, _opts), do: {:ok, "ok"}

    @impl true
    def complete_plan(_plan, _opts), do: {:ok, "ok"}
  end

  defmodule NonportableCatalog do
    @behaviour Spectre.Prism.Adapter
    @behaviour Spectre.LLM

    @impl true
    def catalog do
      %{
        options: [callback: fn -> :not_portable end],
        profiles: [nonportable: [model: "nonportable", rank: 40]]
      }
    end

    @impl true
    def complete(_prompt, _opts), do: {:ok, "ok"}

    @impl true
    def complete_plan(_plan, _opts), do: {:ok, "ok"}
  end

  defmodule RaisingCatalog do
    def catalog, do: raise("catalog failed")
  end

  defmodule ThrowingCatalog do
    def catalog, do: throw(:catalog_failed)
  end

  defmodule ExitingCatalog do
    def catalog, do: exit(:catalog_failed)
  end

  defmodule EmptyCatalog do
    def catalog, do: %{profiles: []}
    def complete_plan(_plan, _opts), do: {:ok, "ok"}
  end

  defmodule InvalidOptionsCatalog do
    def catalog, do: %{profiles: [one: [model: "one", rank: 10]], options: %{bad: true}}
    def complete_plan(_plan, _opts), do: {:ok, "ok"}
  end

  defmodule MissingCompletion do
    def catalog, do: %{profiles: [one: [model: "one", rank: 10]]}
  end

  defmodule MissingEmbeddingCallbacks do
    def catalog, do: %{profiles: [one: [model: "one", rank: 10]]}
    def complete_plan(_plan, _opts), do: {:ok, "ok"}
  end

  defmodule MissingModel do
    def catalog, do: %{profiles: [one: [rank: 10]]}
    def complete_plan(_plan, _opts), do: {:ok, "ok"}
  end

  defmodule InvalidProfileOptions do
    def catalog, do: %{profiles: [{:one, [:not_a_keyword]}]}
    def complete_plan(_plan, _opts), do: {:ok, "ok"}
  end
end

defmodule Spectre.Prism.RegistryHardeningTest do
  use ExUnit.Case, async: true

  alias Spectre.Prism.Adapters.OpenAI
  alias Spectre.Prism.Registry
  alias Spectre.Prism.RegistryHardeningTest.Adapters.EmptyCatalog
  alias Spectre.Prism.RegistryHardeningTest.Adapters.ExitingCatalog
  alias Spectre.Prism.RegistryHardeningTest.Adapters.ExplicitEmbedding
  alias Spectre.Prism.RegistryHardeningTest.Adapters.InvalidOptionsCatalog
  alias Spectre.Prism.RegistryHardeningTest.Adapters.InvalidProfileOptions
  alias Spectre.Prism.RegistryHardeningTest.Adapters.MissingCompletion
  alias Spectre.Prism.RegistryHardeningTest.Adapters.MissingEmbeddingCallbacks
  alias Spectre.Prism.RegistryHardeningTest.Adapters.MissingModel
  alias Spectre.Prism.RegistryHardeningTest.Adapters.NoCapabilities
  alias Spectre.Prism.RegistryHardeningTest.Adapters.NonportableCatalog
  alias Spectre.Prism.RegistryHardeningTest.Adapters.OtherCapabilities
  alias Spectre.Prism.RegistryHardeningTest.Adapters.RaisingCatalog
  alias Spectre.Prism.RegistryHardeningTest.Adapters.SecretCatalog
  alias Spectre.Prism.RegistryHardeningTest.Adapters.ThrowingCatalog

  test "runtime-only and portable configuration invariants include nested catalog data" do
    assert {:error, {:prism_provider_secret_must_be_runtime, :clientSecret}} =
             Registry.build([{:provider, NoCapabilities, [metadata: %{clientSecret: "secret"}]}])

    assert {:error, :prism_provider_options_must_be_portable} =
             Registry.build([{:provider, NoCapabilities, [owner: self()]}])

    assert {:error, {:prism_provider_secret_must_be_runtime, "X-Api-Key"}} =
             Registry.build([{:secret, SecretCatalog}])

    assert {:error, {:nonportable_prism_provider_catalog, NonportableCatalog}} =
             Registry.build([{:nonportable, NonportableCatalog}])

    assert Registry.runtime_secret(%{nested: [authorization: "Bearer secret"]}) == :authorization
    assert Registry.runtime_secret(max_tokens: 20) == nil
    assert Registry.portable_config?(%{model: {OpenAI, :complete, [model: "one"]}})
    refute Registry.portable_config?(%{callback: fn -> :no end})
    refute Registry.portable_config?(deeply_nested(70))
  end

  test "catalog exceptions, throws, and exits become compilation errors" do
    assert {:error, {:invalid_prism_provider_catalog, RaisingCatalog, RuntimeError, message}} =
             Registry.build([{:raising, RaisingCatalog}])

    assert message == "catalog failed"

    assert {:error, {:invalid_prism_provider_catalog, ThrowingCatalog, :throw, :catalog_failed}} =
             Registry.build([{:throwing, ThrowingCatalog}])

    assert {:error, {:invalid_prism_provider_catalog, ExitingCatalog, :exit, :catalog_failed}} =
             Registry.build([{:exiting, ExitingCatalog}])
  end

  test "catalog shape and callback failures are reported precisely" do
    assert {:error, {:empty_prism_provider_catalog, EmptyCatalog}} =
             Registry.build([{:empty, EmptyCatalog}])

    assert {:error, {:invalid_prism_provider_catalog_options, InvalidOptionsCatalog}} =
             Registry.build([{:options, InvalidOptionsCatalog}])

    assert {:error, {:missing_prism_provider_completion, MissingCompletion}} =
             Registry.build([{:completion, MissingCompletion}])

    assert {:error, {:invalid_prism_provider_profiles, InvalidProfileOptions}} =
             Registry.build([{:profiles, InvalidProfileOptions}])

    assert {:error, {:missing_prism_provider_model, :missing, :one}} =
             Registry.build([{:missing, MissingModel}])

    assert {:error, {:missing_prism_provider_embedding_callbacks, MissingEmbeddingCallbacks}} =
             Registry.build([
               {:missing_embedding, MissingEmbeddingCallbacks, [embedding: "custom-embedding"]}
             ])
  end

  test "auto classifier and embedding survive unrelated provider registrations" do
    assert {:ok, registry} =
             Registry.build([{:openai, OpenAI}, {:unrelated, NoCapabilities}])

    assert {OpenAI, _embedding_opts} = Registry.embedding(registry)
    assert registry.classifier_profile == :fast

    assert {:ok, reversed} =
             Registry.build([{:unrelated, NoCapabilities}, {:openai, OpenAI}])

    assert {OpenAI, _embedding_opts} = Registry.embedding(reversed)
    assert reversed.classifier_profile == :fast

    assert {:ok, ambiguous} =
             Registry.build([{:openai, OpenAI}, {:other, OtherCapabilities}])

    assert Registry.embedding(ambiguous) == nil
    assert Registry.classifier(ambiguous) == nil
  end

  test "explicit selections remain deterministic across providers" do
    assert {:ok, registry} =
             Registry.build([
               {:openai, OpenAI, [classifier: false, embedding: false]},
               {:explicit, ExplicitEmbedding,
                [classifier: false, embedding: [model: "explicit-vector", dimensions: 2]]}
             ])

    assert {ExplicitEmbedding, opts} = Registry.embedding(registry)
    assert opts[:model] == "explicit-vector"

    assert {:error, :multiple_prism_embedding_adapters} =
             Registry.build([
               {:openai, OpenAI, [classifier: false, embedding: true]},
               {:other, OtherCapabilities, [classifier: false, embedding: true]}
             ])

    assert {:error, :multiple_prism_classifier_adapters} =
             Registry.build([
               {:openai, OpenAI, [classifier: true, embedding: false]},
               {:other, OtherCapabilities, [classifier: true, embedding: false]}
             ])
  end

  test "registration and model selection reject duplicates and malformed overrides" do
    registry = Registry.new()
    assert {:ok, registry} = Registry.register(registry, :one, NoCapabilities)
    assert {:ok, registration} = Registry.fetch(registry, :one)
    assert registration.id == :one
    assert {:error, {:unknown_prism_provider, :missing}} = Registry.fetch(registry, :missing)

    assert {:error, {:duplicate_prism_provider, :one}} =
             Registry.register(registry, :one, NoCapabilities)

    assert_raise ArgumentError, ~r/duplicate_prism_provider/, fn ->
      Registry.register!(registry, :one, NoCapabilities)
    end

    assert {:error, {:invalid_prism_provider_declarations, :invalid}} = Registry.build(:invalid)

    assert {:error, {:invalid_prism_provider_declaration, :invalid}} =
             Registry.build([:invalid])

    assert {:error, {:unknown_prism_provider_level, :missing}} =
             Registry.build([{:openai, OpenAI, [levels: [:missing]]}])

    assert {:error, {:invalid_prism_provider_levels, :fast}} =
             Registry.build([{:openai, OpenAI, [levels: :fast]}])

    assert {:error, {:duplicate_prism_provider_model, :fast}} =
             Registry.build([{:openai, OpenAI, [models: [fast: "one", fast: "two"]]}])

    assert {:error, {:unknown_prism_provider_model, :unknown}} =
             Registry.build([{:openai, OpenAI, [models: [unknown: "one"]]}])

    assert {:error, {:invalid_prism_provider_model_override, [:not_a_keyword]}} =
             Registry.build([{:openai, OpenAI, [models: [fast: [:not_a_keyword]]]}])
  end

  defp deeply_nested(0), do: :value
  defp deeply_nested(depth), do: [deeply_nested(depth - 1)]
end
