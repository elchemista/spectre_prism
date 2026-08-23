# Spectre Prism public API — 0.1.0

This file is the normative public API manifest for Spectre Prism `0.1.0`.
Its package and Stack contracts target Spectre `0.3.3` from Hex.
Compatibility guarantees
apply only to the modules and callables listed below. Any module, function,
macro, or callback not listed here is an implementation detail even when it is
exported or visible in generated docs.

Default arguments are expanded into every callable arity. For the listed
modules, documented types, opaque types, and documented struct fields are also
public. Modules with no callable row expose only their documented module,
type, and struct contract.

## Manifest

- `Spectre.Prism`
  - functions: `config/1`, `select/3`, `version/0`
  - macros: `default/1`, `level/2`, `prism/1`, `provider/1`, `provider/2`, `provider/3`, `purpose/2`, `selector/1`, `selector/2`
- `Spectre.Prism.Adapter`
  - callbacks: `catalog/0`
- `Spectre.Prism.Adapter.Error`
- `Spectre.Prism.Adapter.ReqLLM`
  - macros: `__using__/1`
- `Spectre.Prism.Adapter.Transport`
  - callbacks: `request/5`
- `Spectre.Prism.Adapters`
  - functions: `built_ins/0`, `fetch/1`, `fetch!/1`, `ids/0`
- `Spectre.Prism.Adapters.OpenAI`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`, `download/1`, `download/2`, `embed/1`, `embed/2`, `load/1`, `load/2`
- `Spectre.Prism.Adapters.OpenRouter`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`, `download/1`, `download/2`, `embed/1`, `embed/2`, `load/1`, `load/2`
- `Spectre.Prism.Adapters.Ollama`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`, `download/1`, `download/2`, `embed/1`, `embed/2`, `load/1`, `load/2`
- `Spectre.Prism.Adapters.Gemini`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`, `download/1`, `download/2`, `embed/1`, `embed/2`, `load/1`, `load/2`
- `Spectre.Prism.Adapters.Anthropic`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`
- `Spectre.Prism.Adapters.DeepSeek`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`
- `Spectre.Prism.Adapters.Groq`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`
- `Spectre.Prism.Adapters.XAI`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`
- `Spectre.Prism.Adapters.Mistral`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`, `download/1`, `download/2`, `embed/1`, `embed/2`, `load/1`, `load/2`
- `Spectre.Prism.Adapters.Cerebras`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`
- `Spectre.Prism.Adapters.Bumblebee`
  - functions: `complete/1`, `complete/2`, `complete_plan/2`, `download/1`, `download/2`, `embed/1`, `embed/2`, `load/1`, `load/2`
- `Spectre.Prism.Config`
- `Spectre.Prism.Profile`
- `Spectre.Prism.Registry`
  - functions: `build/1`, `classifier/1`, `embedding/1`, `fetch/2`, `new/0`, `profiles/1`, `register/3`, `register/4`, `register!/3`, `register!/4`
- `Spectre.Prism.Registry.Registration`
- `Spectre.Prism.Selector.Adaptive`
- `Spectre.Prism.Selector.Rules`
