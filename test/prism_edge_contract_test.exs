defmodule Spectre.Prism.EdgeContractTest.Provider do
  @moduledoc false

  def complete(_prompt, _opts), do: {:ok, "ok"}
  def generate(_prompt, _opts), do: {:ok, "generated"}
end

defmodule Spectre.Prism.EdgeContractTest do
  use ExUnit.Case, async: true

  alias Spectre.Context
  alias Spectre.Inference.Request
  alias Spectre.Input
  alias Spectre.Prism.Config
  alias Spectre.Prism.Extension
  alias Spectre.Prism.Profile
  alias Spectre.Prism.Selector.Adaptive
  alias Spectre.Prism.Selector.Rules
  alias Spectre.Prompt.Plan
  alias Spectre.State

  @provider Spectre.Prism.EdgeContractTest.Provider

  test "package compiler rejects duplicate and ambiguous declarations" do
    assert Spectre.Prism.version() == "0.1.5"

    assert {:error, {:duplicate_prism_level, :fast}} =
             compile_stack("""
             level(:fast, model: :first)
             level(:fast, model: :second)
             """)

    assert {:error, {:duplicate_prism_profile, :fast}} =
             compile_stack("""
             model(:fast, :first)
             level(:fast, model: :second)
             """)

    assert {:error, {:duplicate_prism_declaration, :default}} =
             compile_stack("""
             default(:fast)
             default(:deep)
             """)

    assert {:error, {:duplicate_prism_declaration, :selector}} =
             compile_stack("""
             selector(Spectre.Prism.Selector.Rules)
             selector(Spectre.Prism.Selector.Adaptive, reason: :custom)
             """)
  end

  test "Stack model declarations resolve every supported provider shape" do
    assert {:ok, config} =
             compile_extension(%{
               providers: [
                 module: @provider,
                 pair: {@provider, :generate},
                 triple: {@provider, :generate, temperature: 0.1}
               ],
               models: [
                 {:fast, [provider: :module, id: "small"]},
                 {:balanced, [provider: :pair, id: "medium"]},
                 {:deep, [provider: :triple, id: "large"]},
                 {:custom, [module: @provider, function: :generate, id: "custom", rank: 40]},
                 {:direct, [adapter: {@provider, :complete, []}, rank: 50]},
                 {:explicit, [model: :already_resolved, rank: 60]}
               ],
               default: :balanced
             })

    assert config.default == :balanced
    assert config.max_attempts == 2
    assert config.selector == {Adaptive, []}

    models = Map.new(config.profiles, &{&1.id, &1.model})
    assert models.fast == {@provider, :complete, model: "small"}
    assert models.balanced == {@provider, :generate, model: "medium"}
    assert models.deep == {@provider, :generate, [model: "large", temperature: 0.1]}
    assert models.custom == {@provider, :generate, model: "custom"}
    assert models.direct == {@provider, :complete, []}
    assert models.explicit == :already_resolved
  end

  test "extension compilation reports invalid model and provider configurations" do
    assert {:error, {:invalid_prism_stack_config, :invalid}} =
             Extension.compile(__MODULE__, stack_config: :invalid)

    assert {:error, :prism_requires_at_least_one_level} = compile_extension(%{})

    assert {:error, {:invalid_prism_model_options, :fast, [:not_a_keyword]}} =
             compile_extension(%{models: [fast: [:not_a_keyword]]})

    assert {:error, {:unknown_prism_provider, :missing}} =
             compile_extension(%{models: [fast: [provider: :missing]]})

    assert {:error, {:prism_model_requires_provider, :fast}} =
             compile_extension(%{models: [fast: [id: "small"]]})

    assert {:error, {:ambiguous_prism_model_provider, :fast}} =
             compile_extension(%{
               providers: [one: @provider, two: @provider],
               models: [fast: [id: "small"]]
             })

    assert {:error, {:invalid_prism_provider, "invalid"}} =
             compile_extension(%{
               providers: [provider: "invalid"],
               models: [fast: [provider: :provider]]
             })

    assert {:error, {:invalid_prism_provider_options, [:not_a_keyword]}} =
             compile_extension(%{
               providers: [provider: {@provider, :complete, [:not_a_keyword]}],
               models: [fast: [provider: :provider]]
             })
  end

  test "extension compilation validates profiles, purposes, selector, and attempts" do
    assert {:error, {:invalid_prism_profile, message}} =
             compile_extension(%{levels: [custom: [model: :custom]]})

    assert message =~ "requires rank"

    assert {:error, {:unknown_prism_default, :missing}} =
             compile_extension(%{levels: base_levels(), default: :missing})

    assert {:error, {:invalid_prism_purpose, :chat, {:unknown_level, :missing}}} =
             compile_extension(%{
               levels: base_levels(),
               purposes: [chat: [minimum: :missing]]
             })

    assert {:error, {:invalid_prism_selector, "invalid"}} =
             compile_extension(%{levels: base_levels(), selector: "invalid"})

    assert {:error, {:invalid_prism_selector_options, [:not_a_keyword]}} =
             compile_extension(%{
               levels: base_levels(),
               selector: {Rules, [:not_a_keyword]}
             })

    assert {:error, {:invalid_prism_max_attempts, 0}} =
             compile_extension(%{levels: base_levels(), options: [max_attempts: 0]})
  end

  test "flow constraints preserve unrelated options and reject unknown levels" do
    {:ok, config} = compile_extension(%{levels: base_levels()})

    assert {[], [timeout: 10]} = Extension.flow_constraints([timeout: 10], config)

    assert {[constraint], [timeout: 10]} =
             Extension.flow_constraints(
               [prism: %{minimum: :balanced}, timeout: 10],
               config
             )

    assert constraint.namespace == :prism
    assert constraint.kind == :inference
    assert constraint.values == [[minimum: :balanced]]

    assert {:error, {:unknown_level, :missing}} =
             Extension.flow_constraints([prism: [minimum: :missing]], config)

    assert {:error, {:invalid_prism_flow_constraint, :invalid}} =
             Extension.flow_constraints([prism: :invalid], config)

    assert {Adaptive, selector_opts} = Extension.inference_selector(config)
    assert selector_opts[:config] == config
    assert selector_opts[:profiles] == config.profiles
    assert selector_opts[:max_attempts] == 2
  end

  test "selection fails clearly for strict and unresolved model choices" do
    profiles = profiles()
    config = %Config{profiles: profiles, default: :balanced}
    context = context()

    unresolved =
      request(
        constraints: [preferred_level: :balanced],
        metadata: %{}
      )

    assert {:error, {:missing_model_for_profile, :balanced}} =
             Rules.select(unresolved, profiles, context, config: config)

    strict =
      request(
        constraints: [preferred_level: :deep, strict?: true],
        metadata: %{previous_levels: [:deep], agent_model: :agent}
      )

    assert {:error, {:strict_inference_profile_unavailable, :deep}} =
             Rules.select(strict, profiles, context, config: config)
  end

  test "adaptive selection escalates risk, modality, and retry without inspecting content" do
    profiles = profiles()
    config = %Config{profiles: profiles, default: :fast}
    context = context()

    for {attrs, reason} <- [
          {[constraints: [risk: :high]], :high_risk},
          {[modalities: [:text, :image]], :multimodal},
          {[attempt: 2, metadata: %{previous_levels: [:fast]}], :compatible_fallback}
        ] do
      assert {:ok, selection} =
               attrs
               |> request()
               |> Adaptive.select(profiles, context, config: config)

      assert selection.level == :deep
      assert selection.reason == reason
    end
  end

  test "explicit fallback chains obey the configured minimum level" do
    profiles = [
      Profile.new(:fast, model: :fast, fallback: [:deep, :balanced]),
      Profile.new(:balanced, model: :balanced),
      Profile.new(:deep, model: :deep)
    ]

    config = %Config{profiles: profiles, default: :fast}

    assert {:ok, selection} =
             request(constraints: [preferred_level: :fast, minimum_level: :fast])
             |> Rules.select(profiles, context(), config: config)

    assert selection.fallback_chain == [:deep, :balanced]
  end

  test "custom profile levels require an explicit rank" do
    assert_raise ArgumentError, ~r/requires rank/, fn ->
      Profile.new(:custom, model: :custom)
    end
  end

  defp compile_stack(source) do
    {block, _binding} = Code.eval_string("quote do\n#{source}\nend")
    Spectre.Prism.compile([], block, __ENV__)
  end

  defp compile_extension(overrides) do
    stack_config =
      %{
        providers: [],
        models: [],
        levels: [],
        purposes: [],
        default: nil,
        selector: nil,
        options: []
      }
      |> Map.merge(overrides)

    Extension.compile(__MODULE__, stack_config: stack_config)
  end

  defp base_levels do
    [
      fast: [model: :fast],
      balanced: [model: :balanced],
      deep: [model: :deep]
    ]
  end

  defp profiles do
    [
      Profile.new(:fast, model: :fast),
      Profile.new(:balanced, model: :agent_default),
      Profile.new(:deep,
        model: :deep,
        supports: [:text, :image, :structured_output]
      )
    ]
  end

  defp request(attrs) do
    {:ok, plan} = Plan.compose("prompt", [], [:agent])

    attrs
    |> Map.new()
    |> Map.put_new(:purpose, :response_generation)
    |> Map.put_new(:plan, plan)
    |> Request.new()
  end

  defp context do
    %Context{
      agent: __MODULE__,
      input: Input.new("hello"),
      state: %State{}
    }
  end
end
