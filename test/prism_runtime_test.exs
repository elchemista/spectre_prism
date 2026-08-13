defmodule Spectre.Prism.RuntimeTest.Model do
  def complete(_prompt, opts) do
    model = Keyword.get(opts, :model, "unknown")
    if pid = Keyword.get(opts, :test_pid), do: send(pid, {:model_called, model, opts[:purpose]})

    cond do
      opts[:purpose] == :classifier -> {:ok, "CLASSIFIED"}
      model == "reasoning-fails" -> {:error, :model_unavailable}
      true -> {:ok, "reply from #{model}"}
    end
  end
end

defmodule Spectre.Prism.RuntimeTest.Agent do
  use Spectre.Agent, prompt_root: "test/fixtures/prompts"

  model(Spectre.Prism.RuntimeTest.Model, model: "balanced")

  classifier(Spectre.Prism.RuntimeTest.Model,
    model: "legacy-classifier",
    llm_opts: [temperature: 0.0]
  )

  router(via: [:regex, :llm_classifier])

  use Spectre.Prism, max_attempts: 2

  prism do
    level(:fast,
      model: {Spectre.Prism.RuntimeTest.Model, :complete, model: "small"}
    )

    level(:balanced,
      model: :agent_default
    )

    level(:deep,
      model: {Spectre.Prism.RuntimeTest.Model, :complete, model: "reasoning"}
    )

    purpose(:route_classification, prefer: :fast)
    default(:balanced)
    selector(Spectre.Prism.Selector.Adaptive)
  end

  flow :fast do
    on :fast_question, regex: ~r/^fast$/ do
      ask(:answer, intelligence: :fast)
    end
  end

  flow :deep do
    on :deep_question, regex: ~r/^deep$/ do
      ask(:answer, intelligence: :deep)
    end
  end

  flow :classified do
    on :CLASSIFIED do
      ask(:answer)
    end
  end
end

defmodule Spectre.Prism.RuntimeTest.FallbackAgent do
  use Spectre.Agent, prompt_root: "test/fixtures/prompts"
  model(Spectre.Prism.RuntimeTest.Model, model: "balanced")
  use Spectre.Prism, max_attempts: 2

  prism do
    level(:fast,
      model: {Spectre.Prism.RuntimeTest.Model, :complete, model: "small"}
    )

    level(:balanced,
      model: :agent_default
    )

    level(:deep,
      model: {Spectre.Prism.RuntimeTest.Model, :complete, model: "reasoning-fails"}
    )

    default(:balanced)
  end

  flow :fallback, prism: [prefer: :deep] do
    on :fallback_question, regex: ~r/^fallback$/ do
      ask(:answer)
    end
  end

  flow :strict_minimum do
    on :strict_question, regex: ~r/^strict$/ do
      ask(:answer, intelligence: :deep)
    end
  end
end

defmodule Spectre.Prism.RuntimeTest do
  use ExUnit.Case, async: true

  alias Spectre.Context
  alias Spectre.Inference.Request
  alias Spectre.Input
  alias Spectre.Prism.RuntimeTest.Agent
  alias Spectre.Prism.RuntimeTest.FallbackAgent
  alias Spectre.Prism.RuntimeTest.Model
  alias Spectre.Prism.Selector.Rules
  alias Spectre.Prompt.Plan
  alias Spectre.State

  test "intelligence selects a semantic level per inference" do
    assert {:ok, result} = Spectre.ask(Agent, "fast", test_pid: self())
    assert result.reply_text == "reply from small"
    assert result.metadata.inference.selection.level == :fast
    assert result.metadata.inference.selection.reason == :adaptive_preference
    assert_receive {:model_called, "small", _purpose}

    assert {:ok, result} = Spectre.ask(Agent, "deep", test_pid: self())
    assert result.reply_text == "reply from reasoning"
    assert result.metadata.inference.selection.level == :deep
    assert_receive {:model_called, "reasoning", _purpose}
  end

  test "route classification and response generation receive separate selections" do
    assert {:ok, config} = Spectre.Prism.config(Agent)

    assert Enum.find(config.profiles, &(&1.id == :balanced)).model ==
             {Model, :complete, model: "balanced"}

    assert {:ok, result} = Spectre.ask(Agent, "not a regex", test_pid: self())
    assert result.route.label == :CLASSIFIED
    assert result.metadata.inference.selection.level == :balanced

    assert_receive {:model_called, "small", :classifier}
    assert_receive {:model_called, "balanced", _response_purpose}
  end

  test "a compatible provider failure falls back with a bounded second selection" do
    assert {:ok, result} = Spectre.ask(FallbackAgent, "fallback", test_pid: self())
    assert result.reply_text == "reply from balanced"
    assert result.metadata.inference.selection.level == :balanced
    assert result.metadata.inference.selection.attempt == 2
    assert_receive {:model_called, "reasoning-fails", _purpose}
    assert_receive {:model_called, "balanced", _purpose}
  end

  test "intelligence minimum is never downgraded during fallback" do
    assert {:error, {:no_compatible_inference_profile, _constraints}} =
             Spectre.ask(FallbackAgent, "strict", test_pid: self())

    assert_receive {:model_called, "reasoning-fails", _purpose}
    refute_receive {:model_called, "balanced", _purpose}, 50
  end

  test "hard modality and privacy constraints fail clearly" do
    {:ok, config} = Spectre.Prism.config(Agent)
    {:ok, plan} = Plan.compose("audio", [], [:agent])

    request =
      Request.new(%{
        purpose: :multimodal_understanding,
        plan: plan,
        modalities: [:audio],
        constraints: [privacy: :local_only],
        metadata: %{agent_model: {Model, :complete, []}}
      })

    ctx = %Context{
      agent: Agent,
      input: Input.new(""),
      state: %State{}
    }

    assert {:error, {:no_compatible_inference_profile, constraints}} =
             Rules.select(
               request,
               config.profiles,
               ctx,
               config: config
             )

    assert constraints.privacy == :local_only
  end

  test "unknown flow levels fail at Agent compilation" do
    module = Module.concat(__MODULE__, "Unknown#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Spectre.Agent
      model Spectre.Prism.RuntimeTest.Model
      use Spectre.Prism

      prism do
        level :balanced, model: :agent_default
      end

      flow :invalid, prism: [minimum: :missing] do
        on :question, regex: ~r/question/ do
          ask "answer"
        end
      end
    end
    """

    assert_raise ArgumentError, ~r/unknown_level/, fn ->
      Code.compile_string(source)
    end
  end
end
