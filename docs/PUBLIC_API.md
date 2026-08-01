# Spectre Prism public API — 0.2.0

This file is the normative public API manifest for Spectre Prism `0.2.0`. It
retains the recoverable `0.1.6` surface while aligning the package and Stack
contracts with Spectre `0.2.0`. Compatibility guarantees apply only to the
modules and callables listed below. Any module, function, macro, or callback
not listed here is an implementation detail even when it is exported or
visible in generated docs.

Default arguments are expanded into every callable arity. For the listed
modules, documented types, opaque types, and documented struct fields are also
public. Modules with no callable row expose only their documented module,
type, and struct contract.

## Manifest

- `Spectre.Prism`
  - functions: `config/1`, `select/3`, `version/0`
  - macros: `default/1`, `level/2`, `prism/1`, `purpose/2`, `selector/1`, `selector/2`
- `Spectre.Prism.Config`
- `Spectre.Prism.Profile`
- `Spectre.Prism.Selector.Adaptive`
- `Spectre.Prism.Selector.Rules`
