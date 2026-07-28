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
