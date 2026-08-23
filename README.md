# Spectre Prism

`spectre_prism` selects a cognitive profile for every Spectre inference
request. It includes ready-to-use adapters for OpenAI, Anthropic Claude,
Gemini, OpenRouter, Ollama, DeepSeek, Groq, xAI, Mistral, Cerebras, and local
Bumblebee servings. Prism enforces modality,
context-window, privacy, minimum-level, cost, latency, and attempt constraints
before a model is called.

The supported surface is documented in the
[public API manifest](docs/PUBLIC_API.md).

## Installation

The project is distributed from GitHub:

```elixir
def deps do
  [
    {:spectre, "~> 0.3.3"},
    {:spectre_prism, github: "elchemista/spectre_prism", branch: "main"}
  ]
end
```

Spectre Prism is distributed exclusively from GitHub; there is no Hex package.

## Stack

The shortest setup names a bundled provider. Prism
compiles the adapter catalog into the normal Spectre `:fast`, `:balanced`, and
`:deep` intelligence levels, and contributes a default LLM classifier plus an
embedding adapter when that provider exposes one:

```elixir
defmodule MyApp.AI do
  use Spectre.Stack

  install Spectre.Prism do
    provider :openai
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

`provider :openai`, `provider :anthropic`, `provider :gemini`, and the other
bundled identifiers resolve their adapter automatically. Common aliases
`:claude`, `:google`, and `:grok` are accepted. Options can follow the provider
directly:

```elixir
provider :deepseek,
  models: [fast: "deepseek-chat", deep: "deepseek-v4-pro"],
  classifier: :fast,
  embedding: false
```

The explicit `provider :my_provider, MyApp.Adapter` form remains available for
application-owned adapters.

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
| `Spectre.Prism.Adapters.Anthropic` | `claude-haiku-4-5` | `claude-sonnet-4-6` | `claude-opus-4-8` | — |
| `Spectre.Prism.Adapters.DeepSeek` | `deepseek-chat` | `deepseek-reasoner` | `deepseek-v4-pro` | — |
| `Spectre.Prism.Adapters.Groq` | `llama-3.1-8b-instant` | `qwen/qwen3-32b` | `openai/gpt-oss-120b` | — |
| `Spectre.Prism.Adapters.XAI` | `grok-4-fast` | `grok-4.20-non-reasoning` | `grok-4.3` | — |
| `Spectre.Prism.Adapters.Mistral` | `mistral-small-latest` | `mistral-medium-latest` | `mistral-large-latest` | `mistral-embed` |
| `Spectre.Prism.Adapters.Cerebras` | `llama3.1-8b` | Qwen 3 235B | `gpt-oss-120b` | — |
| `Spectre.Prism.Adapters.Bumblebee` | `local-small` | `local-medium` | `local-large` | explicit serving |

Every hosted adapter and Ollama use the same ReqLLM bridge. ReqLLM owns each
provider's wire format, authentication, request/response translation, retries,
telemetry, and embedding API; Prism contributes the Spectre contracts and the
fast, balanced, and deep policy catalogs. Gemini is public as `:gemini` in
Prism and maps internally to ReqLLM's `:google` provider.

Credentials are resolved only when an adapter is called:

- OpenAI: `OPENAI_API_KEY`
- OpenRouter: `OPENROUTER_API_KEY`
- Gemini: `GOOGLE_API_KEY`, then `GEMINI_API_KEY`
- Anthropic: `ANTHROPIC_API_KEY`
- DeepSeek: `DEEPSEEK_API_KEY`
- Groq: `GROQ_API_KEY`
- xAI: `XAI_API_KEY`
- Mistral: `MISTRAL_API_KEY`
- Cerebras: `CEREBRAS_API_KEY`
- Ollama: no credential by default; local endpoint
  `http://127.0.0.1:11434/v1`

An `api_key:` is deliberately rejected from compiled provider parameters; Agent
and Stack configuration must not retain secrets. Use the environment variables
above, select another variable with `api_key_env:`, or pass runtime provider
options at the Spectre call boundary.

Catalog and provider configuration is recursively checked before it enters a
Stack. Functions, processes, ports, references, credential headers, tokens,
passwords, and secret keys are rejected; those values belong at the runtime
call boundary only.

Runtime generation options are passed to ReqLLM. Provider-specific values use
`provider_options:` and low-level Req configuration uses `req_http_options:`:

```elixir
receive_timeout: 60_000,
total_timeout: 90_000,
provider_options: [google_thinking_level: :high],
req_http_options: [connect_options: [timeout: 10_000]]
```

ReqLLM errors are reduced to sanitized Prism errors. HTTP status is preserved
for retry decisions, while prompt contents, response bodies, credentials, and
unbounded upstream messages do not cross the adapter boundary.

Models, classifier selection, embeddings, endpoints, and other non-secret
provider parameters are configurable in the optional third argument. Profile
IDs remain the Spectre intelligence levels `:fast`, `:balanced`, and `:deep`:

```elixir
install Spectre.Prism do
  provider :openai,
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

### Any ReqLLM provider

The bridge can wrap a ReqLLM provider that does not yet have a named Prism
module. Only the catalog policy is application-specific:

```elixir
defmodule MyApp.VeniceAdapter do
  use Spectre.Prism.Adapter.ReqLLM,
    provider: :venice,
    api_key_env: "VENICE_API_KEY",
    profiles: [
      fast: [model: "venice-fast", rank: 10],
      balanced: [model: "venice-balanced", rank: 20],
      deep: [model: "venice-deep", rank: 30]
    ]
end

install Spectre.Prism do
  provider :venice, MyApp.VeniceAdapter
end
```

The `model`, `base_url`, `api_key_env`, and `model_extra` options form the
ReqLLM model specification. Generation options such as `temperature`,
`max_tokens`, `reasoning_effort`, `provider_options`, `receive_timeout`, and
`total_timeout` pass through to ReqLLM. Secrets must still be supplied by the
environment or at the runtime call boundary.

The named adapters can also be called directly; their balanced generation and
default embedding models are filled automatically:

```elixir
{:ok, response} =
  Spectre.Prism.Adapters.Gemini.complete("Explain OTP supervision",
    reasoning_effort: :high
  )

{:ok, vector} =
  Spectre.Prism.Adapters.OpenAI.embed("semantic search input",
    dimensions: 768
  )
```

Multiple providers may coexist when their profile identifiers are unique.
Map each catalog level to an application-owned identifier:

```elixir
install Spectre.Prism do
  provider :anthropic,
    levels: [fast: :claude_fast, balanced: :claude_balanced, deep: :claude_deep]

  provider :deepseek,
    levels: [
      fast: :deepseek_fast,
      balanced: :deepseek_balanced,
      deep: :deepseek_deep
    ]

  default :claude_balanced
end
```

### Local Bumblebee

Bumblebee is optional. Add `{:bumblebee, "~> 0.7"}` to the host application,
load the model/tokenizer, and supervise the resulting serving:

```elixir
children = [
  {Nx.Serving, serving: text_generation_serving, name: MyApp.TextGeneration}
]
```

Then register the serving name as portable Prism configuration:

```elixir
install Spectre.Prism do
  provider :bumblebee,
    serving: MyApp.TextGeneration,
    models: [
      fast: "local-small",
      balanced: "local-medium",
      deep: "local-large"
    ],
    embedding: false

  default :balanced
end
```

For separate models, use `servings: %{"local-small" => MyApp.SmallServing,
"local-large" => MyApp.LargeServing}`. Local embeddings are opt-in with
`embedding_serving:` and an explicit
`embedding: [model: "local-embedding", dimensions: dimension]`.

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

That configuration is re-resolved for every
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
