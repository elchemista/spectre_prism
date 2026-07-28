defmodule Spectre.Prism.StackContractTest.OpenRouter do
  @moduledoc false
end

defmodule Spectre.Prism.StackContractTest.Stack do
  @moduledoc false

  use Spectre.Stack, id: :prism_contract

  install Spectre.Prism, policy: :balanced do
    provider(:openrouter, Spectre.Prism.StackContractTest.OpenRouter)
    model(:fast, id: "small-model")
    model(:reasoning, id: "reasoning-model")
  end
end

defmodule Spectre.Prism.StackContractTest do
  use ExUnit.Case, async: true

  alias Spectre.Prism.StackContractTest.Stack
  alias Spectre.Stack.Contract.V1
  alias Spectre.Stack.Definition
  alias Spectre.Stack.Runtime

  test "publishes a compatible V1 manifest without fake capabilities" do
    assert {:ok, package} = V1.verify_installable(Spectre.Prism)

    assert package.id == :prism
    assert package.version == "0.1.2"
    assert package.contract == 1
    assert package.spectre == "~> 0.1.2"
    assert package.dsl == Spectre.Prism
    assert package.provides == []
    assert package.operations == []
    assert package.actions == []
    assert package.resources == []
  end

  test "compiles providers and models inside a real Stack" do
    assert {:ok, installation} = Definition.installation(Stack, :prism)

    assert installation.config == %{
             options: [policy: :balanced],
             providers: [
               {:openrouter, Spectre.Prism.StackContractTest.OpenRouter}
             ],
             models: [
               {:fast, [id: "small-model"]},
               {:reasoning, [id: "reasoning-model"]}
             ]
           }

    assert Stack.__spectre_stack_manifest__() == Definition.manifest(Stack)
  end

  test "rejects duplicate provider and model identifiers independently" do
    duplicate_provider =
      quote do
        provider(:openrouter, FirstProvider)
        provider(:openrouter, SecondProvider)
      end

    duplicate_model =
      quote do
        model(:fast, id: "first")
        model(:fast, id: "second")
      end

    assert {:error, {:duplicate_prism_provider, :openrouter}} =
             Spectre.Prism.compile([], duplicate_provider, __ENV__)

    assert {:error, {:duplicate_prism_model, :fast}} =
             Spectre.Prism.compile([], duplicate_model, __ENV__)
  end

  test "does not invent runtime resources" do
    assert {:ok, []} = Runtime.child_specs(Stack)

    assert {:error, {:unknown_stack_capability, :service, :prism}} =
             Definition.resolve(Stack, :service, :prism)
  end
end
