defmodule Spectre.Prism.ServerToolTest do
  use ExUnit.Case, async: true

  alias Spectre.Prism.ServerTool

  defmodule Provider do
    def complete(_prompt, _opts), do: {:ok, "unused"}
  end

  defmodule Stack do
    use Spectre.Stack

    install Spectre.Prism do
      provider(:test, Provider)
      model(:fast, id: "small-model")
      default(:fast)
    end
  end

  defmodule Agent do
    use Spectre.Agent, stack: Stack
  end

  defmodule ContextSelector do
    def select(request, profiles, context, opts) do
      send(context.opts[:test_pid], {:selection_context, context})
      Spectre.Prism.Selector.Adaptive.select(request, profiles, context, opts)
    end
  end

  defmodule ContextStack do
    use Spectre.Stack

    install Spectre.Prism do
      provider(:test, Provider)
      model(:fast, id: "small-model")
      default(:fast)
      selector(ContextSelector)
    end
  end

  defmodule ContextAgent do
    use Spectre.Agent, stack: ContextStack
  end

  test "tool is cognitive and rejects provider/model overrides in request data" do
    tools = Spectre.Prism.tools(%{})
    assert tools.prism.operations.select.path == :cognitive
    assert Spectre.Stack.Tools.validate!(tools) == tools

    assert {:error, :invalid_prism_selection_request} =
             ServerTool.prepare(:select, %{purpose: :answer, model: :injected}, %{})
  end

  test "real installed selector returns a portable public summary" do
    assert {:ok, args} = ServerTool.prepare(:select, %{purpose: :response_generation}, %{})

    context = %{
      agent: Agent,
      command_id: "select-1",
      assigns: %{},
      input: nil,
      options: [],
      routing: %{}
    }

    raw = ServerTool.invoke(:select, args, %{service_context: context})
    assert {:ok, {:selected, selected}} = ServerTool.project(:select, raw)
    assert selected.level == :fast
    assert selected.request_id == "select-1"
    refute Map.has_key?(selected, :model)
    refute Map.has_key?(selected, :metadata)
    assert {:ok, _} = Spectre.GAM.Canonical.Value.encode(selected)
  end

  test "custom selectors receive route, memory and initialized state as in generation" do
    route = %Spectre.Route{label: :pricing, owner: ContextAgent, scope: :agent}
    memory = %{facts: ["already contacted"]}

    service = %{
      agent: ContextAgent,
      command_id: "select-context",
      assigns: %{locale: :it},
      input: "hello",
      options: [test_pid: self()],
      routing: %{route: route},
      memory: memory
    }

    assert {:ok, _} =
             ServerTool.invoke(:select, %{purpose: :response_generation}, %{
               service_context: service
             })

    assert_receive {:selection_context, context}
    assert context.route == route
    assert context.memory == memory
    assert %Spectre.State{} = context.state
    assert context.input.text == "hello"
    assert context.assigns.locale == :it
  end
end
