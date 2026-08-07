# Spectre Prism

`spectre_prism` selects a cognitive profile for every Spectre inference
request. It includes a provider-adapter registry for OpenAI, OpenRouter,
Ollama, and the Gemini API. Prism enforces modality,
context-window, privacy, minimum-level, cost, latency, and attempt constraints
before a model is called.

The exact `0.2.0` compatibility surface is published in the
[public API manifest](docs/PUBLIC_API.md).

## 0.2.0 Spectre Compatibility

Version `0.2.0` aligns Prism's package, inference selector, and Stack contracts
with the Spectre `0.2.0` GitHub tag. Prism still makes a fail-closed capability selection;
provider execution, Runs, operational loops, and persistence remain owned by
the core and host application.

## 0.1.6 Recoverable Baseline

Version `0.1.6` is a consolidation-only release with no new runtime feature and
no intentional breaking change. Elixir 1.19 on Erlang/OTP 28 is the initially
guaranteed pair. Uniform CI runs format, warnings-as-errors compilation, tests,
non-strict Credo, Dialyzer, and ExDoc. The changelog, Apache-2.0 license, and
explicit API manifest complete the
release boundary before `0.2.0` development begins.

## Installation

The project is distributed from GitHub:

```elixir
def deps do
  [
    {:spectre_prism, github: "elchemista/spectre_prism", tag: "v0.2.0"}
  ]
end
```

Spectre Prism is distributed exclusively from GitHub; there is no Hex package.

## Stack

The shortest setup passes a provider identifier and an adapter module. Prism
compiles the adapter catalog into the normal Spectre `:fast`, `:balanced`, and
`:deep` intelligence levels, and contributes a default LLM classifier plus an
embedding adapter:

```elixir
defmodule MyApp.AI do
  use Spectre.Stack

  install Spectre.Prism do
    provider :openai, Spectre.Prism.Adapters.OpenAI
    default :balanced
  end
end

defmodule MyApp.Agent do
  use Spectre.Agent, stack: MyApp.AI

  # Enable only the routing evidence required by the application.
  router via: [:regex, :embedding, :llm_classifier]
end
```

`intelligence` is not a provider registration DSL. It remains Spectre's
per-inference level constraint:

```elixir
ask :answer, intelligence: :deep
```

The provider identifier is application-owned; the second argument is always
the module implementing `Spectre.Prism.Adapter` and `Spectre.LLM`. A third,
optional keyword list configures that adapter.

`classifier:` configures Spectre's `:llm_classifier` adapter. The selected
embedding is also contributed to Spectre's `:embedding` router and to the
classifier encoder options. A trained local classifier artifact is still
application-owned; registering a provider does not train one implicitly.

### Bundled provider adapters

| Adapter module | Fast | Balanced | Deep | Embedding |
| --- | --- | --- | --- | --- |
| `Spectre.Prism.Adapters.OpenAI` | `gpt-5.6-luna` | `gpt-5.6-terra` | `gpt-5.6-sol` | `text-embedding-3-small` |
| `Spectre.Prism.Adapters.OpenRouter` | OpenAI Luna route | OpenAI Terra route | OpenAI Sol route | OpenAI embedding route |
| `Spectre.Prism.Adapters.Ollama` | `qwen3.5:0.8b` | `qwen3.5:9b` | `qwen3.5:35b` | `embeddinggemma` |
| `Spectre.Prism.Adapters.Gemini` | `gemini-3.5-flash-lite` | `gemini-3.6-flash` | `gemini-3.5-flash` | `gemini-embedding-2` |

Credentials are resolved only when an adapter is called:

- OpenAI: `OPENAI_API_KEY`
- OpenRouter: `OPENROUTER_API_KEY`
- Gemini: `GOOGLE_API_KEY`, then `GEMINI_API_KEY`
- Ollama: no credential by default; local endpoint
  `http://127.0.0.1:11434`

An `api_key:` is deliberately rejected from compiled provider parameters; Agent
and Stack configuration must not retain secrets. Use the environment variables
above, select another variable with `api_key_env:`, or pass runtime provider
options at the Spectre call boundary.

Models, classifier selection, embeddings, endpoints, and other non-secret
provider parameters are configurable in the optional third argument. Profile
IDs remain the Spectre intelligence levels `:fast`, `:balanced`, and `:deep`:

```elixir
install Spectre.Prism do
  provider :openai, Spectre.Prism.Adapters.OpenAI,
    models: [
      fast: "my-fast-model",
      deep: [model: "my-reasoning-model", rank: 40]
    ],
    classifier: :fast,
    embedding: [model: "text-embedding-3-large", dimensions: 3072],
    base_url: "https://my-gateway.example/v1"

  default :balanced
end
```

Custom adapters implement `Spectre.Prism.Adapter` and `Spectre.LLM`. If their
catalog advertises an embedding, they also implement
`Spectre.Classifier.Embedding`, then register with
`provider :my_provider, MyApp.PrismAdapter`. Adapter parameters, when needed,
are passed as the third argument.

### Existing provider/model DSL

The low-level provider and model declarations remain supported for existing
or application-owned adapters:

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

With Spectre 0.2.0, that configuration is re-resolved for every
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
synchronous in 0.2.0; Prism does not create a second provider scheduler or
continuity lifecycle.

For an Agent-local configuration, `use Spectre.Prism` remains available:

```elixir
defmodule MyApp.LocalAgent do
  use Spectre.Agent
  use Spectre.Prism, max_attempts: 2

  prism do
    # Alternatively: provider :ollama, Spectre.Prism.Adapters.Ollama
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
