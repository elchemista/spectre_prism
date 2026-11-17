# Migrating Prism to Spectre core 0.4

This guide covers integration with Spectre `~> 0.4.0`. Install the compatible
package versions shown in the [README](../README.md), then follow the ownership
and callback changes below. Satellite versions remain independent of core.

## What changes from core 0.3

| Concern | Existing 0.3 application | Core 0.4 application |
| --- | --- | --- |
| Installation | Stack package configuration | Same package registration plus optional `tools/1` descriptor |
| Recognition | Flows and route strategies | Agent keeps declaration-only routes and classifiers |
| Application behavior | Flow bodies / Instance and Run continuation | `Spectre.Server` callbacks and queued commands |
| Tool entry | Direct call / Action provider | Generated helper schedules a command; no import from package |
| Results | Immediate value or Invocation resumption | `handle_result(tag, result, ctx)` after worker result acquisition |
| Effects | Legacy application policies | Automatic AgentServer GAM lifecycle and registered effect adapter |
| Durability | Legacy Run/Instance projection | Server checkpoint, inbox/outbox and typed portable results |

The migration does **not** remove `Spectre.Prism.select/3`, provider adapters and provider/model declarations. Direct calls do not acquire
Server semantics merely because the package is installed. Keep standalone
workflows explicitly caller-owned. Historical examples remain in
[the legacy guide](LEGACY_0_3.md).

## Server callbacks

`use Spectre.Server, tools: MyApp.AI` generates helpers from the installed Stack.
Return the context produced by a helper; the result arrives later through
`handle_result/3` using its `on_result:` tag. Keep process handles outside durable
arguments and assigns. The [core tool guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/STACK_TOOLS.md) defines validation, checkpointing and recovery.

## Selection is not generation

The existing provider/model DSL still configures the Agent's inference profiles.
Move application behavior out of 0.3 `ask`/`act` flow bodies and into Server
callbacks; leave route declarations in `Spectre.Agent`. `generate` automatically
uses the installed selector. No explicit `prism` call is required before it.

For introspection, `prism(ctx, %{purpose: :response_generation}, on_result:
:selected)` returns `{:selected, summary}` without contacting a model. It does
not pin the next generation; the real request is selected with its own prompt,
constraints and current context. Requests may include purpose, constraints and
modalities, but cannot inject a provider/model binding through the helper input.

## Independent classifier and custom providers

Generation, route classification and embeddings can use separate registered
profiles or application adapters. Provider installation does not train a local
classifier, collect intent examples or populate a semantic cache by itself.
Those core routing/training mechanisms remain separate and available.

Custom `select/4` implementations receive the same normalized context as
Server generation: route, memory, assigns, input and host options. Their public
summary excludes executable bindings and credentials. Remote provider secrets
belong in runtime/environment configuration; local Nx servings must be supervised
and referred to by stable name. See [provider setup](PROVIDERS.md).

Prism's helper is cognitive and repeatable. It does not add a governed executor
or a user-consent DSL. Direct adapter `complete`/`embed` and selection APIs remain
available; they are immediate caller-owned operations, not Server commands.
Prism itself continues to require Spectre.


## Migration checklist

1. Pin compatible core and package feature revisions; keep the old dependency
   lockfile available for rollback.
2. Separate Stack installation, Agent routes and Server callbacks.
3. Replace legacy flow effects with explicit helper commands/result handlers;
   retain direct APIs only where caller-owned execution is intentional.
4. Configure named resources and trusted identity required by the package.
5. Configure allowed operations and confirmation in AgentServer; use
   `handle_action/2` for business checks. Spectre constructs GAM records and runs
   the registered executor only after admission.
6. Test refused, uncertain and interrupted paths as well as successful results;
   verify portable snapshots before deploying existing conversations.
7. Review checkpoint/installation changes explicitly; never replay a potentially
   executed effect just to work around a migration error.

## Reusable Skill servers

The same helper works in a mounted Skill Server. Configure GAM on the root;
the mount's `governed:` references restrict its effect operations. Skills share
the root Domain while keeping their own state and checkpoints. See the
[Skill guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/SKILLS.md) for setup and consent routing.
