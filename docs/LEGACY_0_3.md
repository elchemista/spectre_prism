# Historical Spectre 0.3 integration

These examples describe the former Instance/Run integration. They are retained
for maintaining existing applications, **not as the starting architecture for
core 0.4 AgentServer applications**. Use the [0.4 migration guide](MIGRATING_TO_SPECTRE_0_4.md)
and [current README](../README.md) for the new Stack → Agent → Server lifecycle.
A `protect`/policy block below is legacy application DSL; installing a package
never supplies a 0.4 GAM host binding or end-user consent.

### Agent Instance boundary

For subject continuity, submit turns to the unique core-owned Instance:

```elixir
{:ok, instance} =
  Spectre.instance(MyApp.SpectreSupervisor, MyApp.Agent, account_id)

{:ok, turn} = Spectre.turn(instance, "run")
```

Each core Run resolves Prism configuration again when its inference Move is
advanced. Prism selects a compatible cognitive capability, but it does not
create or look up Instances, enqueue Runs, retain Agent State, own the ready
queue or Invocation registry, or schedule provider work. Multi-Run fairness
and observable turn boundaries belong to Spectre core. Inference remains
synchronous; Prism does not create a second provider scheduler or
continuity lifecycle.

For an Agent-local configuration, `use Spectre.Prism` remains available:

```elixir
defmodule MyApp.LocalAgent do
  use Spectre.Agent
  model MyApp.LLM
  use Spectre.Prism, max_attempts: 2

  prism do
    # Alternatively: provider :ollama
    level :fast, model: {MyApp.LLM, :complete, model: "small"}
    level :balanced, model: :agent_default
    level :deep,
      model: {MyApp.LLM, :complete, model: "reasoning"},
      supports: [:text, :structured_output, :vision]

    purpose :route_classification, prefer: :fast
    default :balanced
    selector Spectre.Prism.Selector.Adaptive
  end
end
```

An `:agent_default` level is bound to the Agent's declared `model` while the
immutable Prism profiles are compiled. The Agent must therefore declare that
model before mounting Prism.
