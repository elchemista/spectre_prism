# Provider and model configuration

These are the adapters and bundled defaults implemented by this checkout,
not a claim that every provider/model is currently available in every account.
Override identifiers and credentials for your deployment. Direct adapter calls
remain available; Prism itself depends on Spectre and is not a standalone
framework-independent package. See the [0.4 README](../README.md).

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

Selection is installed by the Stack. In core 0.4, declaration-only flows route
to the Server’s `handle_flow/3` callback; call `generate` there. See the [README](../README.md).
