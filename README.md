# Spectre Prism

`spectre_prism` selects a cognitive profile for every Spectre inference
request. It enforces modality, context-window, privacy, minimum-level, cost,
latency, and attempt constraints before a model is called.

## Installation

The project is distributed from GitHub:

```elixir
def deps do
  [
    {:spectre_prism, github: "elchemista/spectre_prism"}
  ]
end
```

## Stack

```elixir
defmodule MyApp.AI do
  use Spectre.Stack

  install Spectre.Prism, max_attempts: 2 do
    provider :openrouter, MyApp.OpenRouter
    model :fast, id: "small-model"
    model :balanced, id: "balanced-model"
    model :deep, id: "reasoning-model"

    purpose :route_classification, prefer: :fast
    default :balanced
    selector Spectre.Prism.Selector.Adaptive
  end
end
```

Selecting the Stack turns provider/model declarations into executable Spectre
inference profiles and binds Prism's selector to the Agent. No second
`use Spectre.Prism` is required:

```elixir
defmodule MyApp.Agent do
  use Spectre.Agent, stack: MyApp.AI

  flow :analysis, prism: [minimum: :balanced] do
    on :question do
      ask :answer, intelligence: :deep
    end
  end
end
```

Prism selects a compatible profile for every inference request before the
model is called. Modality, context window, privacy, level, cost, latency, and
attempt limits remain fail-closed constraints. Provider clients and secrets
are still supplied by the application; the compiled Stack contains only
portable adapter configuration.

With Spectre 0.1.4, that configuration is re-resolved for every
`Spectre.Runtime.advance/2`. Prism selects inference capabilities inside the
canonical Run step, while provider clients, adapter sessions, processes, and
callbacks remain caller-owned and are never embedded in a `Spectre.Run`
checkpoint. Inference remains synchronous in this release; async provider
scheduling stays outside Prism's selector boundary.

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
synchronous in 0.1.4; later asynchronous scheduling and continuity-plane work
are not part of this release.

For an Agent-local configuration, `use Spectre.Prism` remains available:

```elixir
defmodule MyApp.LocalAgent do
  use Spectre.Agent
  use Spectre.Prism, max_attempts: 2

  prism do
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
