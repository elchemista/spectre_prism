# Changelog

All notable changes to Spectre Prism are documented in this file.

## [Unreleased]

### Added

- Extended the existing Stack and Agent `provider` DSL to accept a Prism
  adapter module plus optional parameters, and added an immutable registry that
  compiles provider catalogs into Spectre intelligence profiles.
- Added OpenAI Responses, OpenRouter Chat Completions, Ollama, and Gemini
  Interactions adapters with fast, balanced, and deep model tiers.
- Added hosted and local embedding integration for Spectre classifier encoding
  and embedding-based routing.
- Added an injectable HTTP transport, runtime-only credential resolution, and
  sanitized retry-aware adapter errors.

### Compatibility

- Spectre's per-inference `intelligence: :fast | :balanced | :deep` contract is
  unchanged. Existing two-argument `provider`, `model`, and `level`
  declarations remain supported.

## [0.2.0] - 2026-08-01

### Changed

- Raised the package, inference selector, and Stack compatibility contracts to
  Spectre 0.2.0.
- Verified fail-closed profile selection and Agent integration against the
  Spectre 0.2.0 operational runtime.

### Compatibility

- Prism remains a capability selector and does not own provider scheduling,
  Runs, Work, Vigil, or Instance lifecycle.

## [0.1.6] - 2026-07-31

### Changed

- Established a recoverable consolidation baseline with an explicit normative
  public API manifest and complete release documentation.
- Added no runtime functionality and made no intentional breaking API change.

## [0.1.5] - 2026-07-30

### Changed

- Raised the library and Stack manifest requirement to Spectre 0.1.5.
- Verified Prism selection inside core-owned Runs without moving provider
  scheduling or lifecycle ownership into Prism.

## [0.1.4] - 2026-07-30

### Changed

- Updated the library, GitHub dependency source, and Stack manifest for
  Spectre 0.1.4 compatibility.
- Documented Prism as a passive cognitive selector inside a core-owned
  subject-scoped Agent Instance.

### Added

- Multi-Run Agent Instance conformance coverage showing that provider
  selection remains package-local while Run scheduling and state stay in core.

### Not included

- Asynchronous provider scheduling and continuity-plane lifecycle remain later
  migration phases.

[Unreleased]: https://github.com/elchemista/spectre_prism/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/elchemista/spectre_prism/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/elchemista/spectre_prism/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/elchemista/spectre_prism/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/elchemista/spectre_prism/compare/v0.1.3...v0.1.4
