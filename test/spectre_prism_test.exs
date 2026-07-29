defmodule Spectre.Prism.StackContractTest.OpenRouter do
  @moduledoc false

  def complete(_prompt, opts) do
    if pid = Keyword.get(opts, :test_pid) do
      send(pid, {:prism_run_provider, Keyword.fetch!(opts, :model)})
    end

    {:ok, "reply from #{Keyword.fetch!(opts, :model)}"}
  end
end

defmodule Spectre.Prism.StackContractTest.Stack do
  @moduledoc false

  use Spectre.Stack, id: :prism_contract

  install Spectre.Prism, max_attempts: 3 do
    provider(:openrouter, Spectre.Prism.StackContractTest.OpenRouter)
    model(:fast, id: "small-model")
    model(:reasoning, id: "reasoning-model")
    purpose(:route_classification, prefer: :fast)
    default(:fast)
    selector(Spectre.Prism.Selector.Rules)
  end
end

defmodule Spectre.Prism.StackContractTest.Agent do
  @moduledoc false

  use Spectre.Agent,
    stack: Spectre.Prism.StackContractTest.Stack,
    prompt_root: "test/fixtures/prompts"

  router(via: [:regex], semantic_cache?: false, classification_log?: false)

  flow :run_contract do
    on :RUN, regex: ~r/^run$/i do
      ask(:answer)
    end
  end
end

defmodule Spectre.Prism.StackContractTest do
  use ExUnit.Case, async: true

  alias Spectre.Context
  alias Spectre.Inference.Request
  alias Spectre.Input
  alias Spectre.Prism.StackContractTest.Agent
  alias Spectre.Prism.StackContractTest.OpenRouter
  alias Spectre.Prism.StackContractTest.Stack
  alias Spectre.Prompt.Plan
  alias Spectre.Run
  alias Spectre.Run.Boundary
  alias Spectre.Runtime, as: SpectreRuntime
  alias Spectre.Stack.Contract.V1
  alias Spectre.Stack.Definition
  alias Spectre.Stack.Runtime

  test "publishes a compatible V1 manifest with the Prism binding" do
    assert {:ok, package} = V1.verify_installable(Spectre.Prism)

    assert package.id == :prism
    assert package.version == "0.1.3"
    assert package.contract == 1
    assert package.spectre == "~> 0.1.3"
    assert package.dsl == Spectre.Prism
    assert package.provides == [{:service, :prism}]
    assert package.operations == []
    assert package.actions == []
    assert package.resources == []
    assert package.agent_extensions == [Spectre.Prism.Extension]
  end

  test "compiles providers and models inside a real Stack" do
    assert {:ok, installation} = Definition.installation(Stack, :prism)

    assert installation.config == %{
             options: [max_attempts: 3],
             providers: [
               {:openrouter, Spectre.Prism.StackContractTest.OpenRouter}
             ],
             models: [
               {:fast, [id: "small-model"]},
               {:reasoning, [id: "reasoning-model"]}
             ],
             levels: [],
             purposes: [route_classification: [prefer: :fast]],
             default: :fast,
             selector: Spectre.Prism.Selector.Rules
           }

    assert Stack.__spectre_stack_manifest__() == Definition.manifest(Stack)
  end

  test "selecting the Stack activates executable Prism profiles without use Prism" do
    assert {:ok, mount} = Spectre.Extension.fetch(Agent, :prism)
    assert mount.module == Spectre.Prism.Extension

    assert {:ok, config} = Spectre.Prism.config(Agent)
    assert config.default == :fast
    assert config.max_attempts == 3
    assert config.selector == {Spectre.Prism.Selector.Rules, []}
    assert config.purposes.route_classification == [prefer: :fast]

    assert Enum.map(config.profiles, & &1.id) == [:fast, :reasoning]

    assert Enum.at(config.profiles, 0).model ==
             {OpenRouter, :complete, model: "small-model"}

    assert Agent.__spectre_definition__().config[:prism] == config

    assert {:ok, plan} = Plan.compose("classify", [], [:agent])

    request =
      Request.new(
        purpose: :route_classification,
        plan: plan
      )

    context = %Context{
      agent: Agent,
      input: Input.new("classify"),
      state: %Spectre.State{}
    }

    assert {:ok, selection} = Spectre.Prism.select(Agent, request, context)
    assert selection.level == :fast

    assert selection.model ==
             {Spectre.Prism.StackContractTest.OpenRouter, :complete, model: "small-model"}
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

  test "keeps SDK clients caller-owned while resolving the Prism service" do
    assert {:ok, []} = Runtime.child_specs(Stack)

    assert {:ok, ref} = Definition.resolve(Stack, :service, :prism)
    assert ref.package == :prism
  end

  test "resolves Prism for each Run advance without checkpointing runtime clients" do
    input = %Input{
      text: "run",
      raw: %{adapter_session: self()},
      meta: %{locale: "it", adapter_session: self()}
    }

    assert {:continue, %Run{} = started} = SpectreRuntime.start(Agent, input)
    assert {:ok, checkpoint} = Run.checkpoint(started)
    assert {:ok, %Run{} = restored} = Run.restore(checkpoint)
    assert restored.input.raw == nil
    assert restored.input.meta == %{locale: "it"}

    assert {:boundary, %Boundary{kind: :reply, output: "reply from small-model"},
            %Run{} = boundary_run} =
             SpectreRuntime.advance(restored, test_pid: self())

    assert_receive {:prism_run_provider, "small-model"}
    assert boundary_run.result.metadata.inference.selection.level == :fast
    assert {:ok, _checkpoint} = Run.checkpoint(boundary_run)
  end
end
