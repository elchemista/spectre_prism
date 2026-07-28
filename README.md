# Spectre Prism

`spectre_prism` owns cognitive provider and model selection configuration for
Spectre. Its version 0.1.2 integration compiles the Stack-local `provider/2`
and `model/2` DSL into immutable data.

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

  install Spectre.Prism do
    provider :openrouter, MyApp.OpenRouter
    model :fast, id: "small-model"
  end
end
```

Installation describes cognitive selection but does not start providers or
authorize models for an Agent.
