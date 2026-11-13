# Spectre Prism for core 0.4

Select the model profile for generation, classification or embeddings without
mixing provider configuration into application handlers. Prism installs into
`Spectre.Stack`; the Agent declares recognition and the Server coordinates
requests and results. Different tasks may use different models, and custom
selectors/providers remain supported.

[Documentation index](docs/INDEX.md) · [Migrate from core 0.3](docs/MIGRATING_TO_SPECTRE_0_4.md)

## Installation on this development branch

This is the **unreleased Spectre core 0.4 integration**. Satellite package
versions are independent; no published Hex 0.4 release is assumed here. Pin
reviewed Git commits for deployment. During development use:

```elixir
defp deps do
  [
    {:spectre, github: "elchemista/spectre",
     branch: "feature/agent-server-gam", override: true},
    {:spectre_prism, github: "elchemista/spectre_prism",
     branch: "feature/stack-tools-0.4"}
  ]
end
```

For sibling checkouts, replace these with `path: "../spectre"` and
`path: "../spectre_prism"` dependencies. Package integration tests use
`SPECTRE_PATH=../spectre mix test`.

Prism depends on Spectre. Its direct provider/selection APIs remain available,
but it is not a framework-independent standalone package. Provider credentials
belong to host environment/runtime configuration, not to prompts or checkpoints.

## Stack → Agent → Server

```elixir
defmodule MyApp.AnswerAI do
  use Spectre.Stack
  install Spectre.Prism do
    provider(:openai)
    default(:balanced)
  end
end

defmodule MyApp.AnswerServer do
  use Spectre.Server, tools: MyApp.AnswerAI, prompt_root: "priv/answer/prompts"

  def handle_flow({:answers, :question}, _input, ctx),
    do: prism(ctx, %{purpose: :response_generation}, on_result: :selected)

  def handle_result(:selected, {:selected, selection}, ctx),
    do: ctx |> assign(:selected_profile, selection.level)
      |> generate(:answer, on_result: :answer)

  def handle_result(:answer, {:generated, response}, ctx),
    do: respond(ctx, response.text)

  def handle_result(tag, result, ctx), do: super(tag, result, ctx)
end

defmodule MyApp.AnswerAgent do
  use Spectre.Agent, stack: MyApp.AnswerAI, server: MyApp.AnswerServer
  flow :answers do
    on(:question, regex: ~r/\S/)
  end
end
```

Create `priv/answer/prompts/answer.eex` and configure provider credentials in
the host. Start `Spectre.Server` with `agent: MyApp.AnswerAgent`; Prism does not
need its own Stack process for remote providers. A local Nx serving is separately
supervised and registered by name, as shown in the [provider guide](docs/PROVIDERS.md).

`prism/3` is a generated helper, not a function to import from `Spectre.Prism`.
Its `:select` operation is **introspection**: it returns the selected profile
summary without calling the model. `generate` makes its own selection for the
actual request, including that prompt's constraints; the introspection result
does not pin a later generation. Calling `generate` directly is sufficient
when you do not need to inspect the choice first.

## Models, routing and results

Prism's ordinary extension continues to serve core generation, classification
and embedding. `provider`, `model`, `purpose`, `default` and `selector` remain
Stack configuration. A classifier may use a separate model or an application
adapter; installing Prism does not train local classifier artifacts or replace
semantic-cache collection/training.

The helper accepts `%{purpose: purpose, constraints: ..., modalities: ...}`
(with optional constraint/modality fields), or `{:select, request}`. It returns
`{:selected, summary}` with public selection information, never executable
model bindings or credentials. Custom selectors receive the same route, memory,
assigns and normalized input context as generation. Errors arrive through the
named `handle_result/3`; cognitive selection is repeatable after recovery.

## Where GAM participates

The [Governed Act Model manifesto](https://spectre.guide/en/governed-act-model)
distinguishes evidence, bounded authority, admitted Acts and unresolved duties.
An installed tool or a model proposal is not user consent. Spectre's default
cognitive path can classify, select, observe and prepare proposals without
requesting end-user permission for every computation. The host declares the
governed surface and its bindings; protected disclosure or resource use can
also belong to that surface. GAM records the governed lifecycle and gates the
host executor. Uncertain effects require reconciliation, not a blind retry.

## Provider setup and compatibility

- [Provider catalogs, custom adapters and local models](docs/PROVIDERS.md)
- [0.4 migration and helper contract](docs/MIGRATING_TO_SPECTRE_0_4.md)
- [Public API contract](docs/PUBLIC_API.md)
- [Historical Instance integration](docs/LEGACY_0_3.md)
- [Changes](CHANGELOG.md)
