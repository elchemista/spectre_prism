# Changelog

All notable changes to Spectre Prism are documented in this file.

## [Unreleased]

### Fixed

- Kept the optional Bumblebee tensor normalizer free of compile-time calls to
  `Nx`, so applications that do not install the optional local-model stack can
  compile Prism with warnings treated as errors.
- Restored the GitHub-only satellite package version to `0.1.0`, keeping
  Prism's release line independent from the Spectre core version.
- Stopped Spectre runtime and host metadata from leaking into ReqLLM provider
  calls, normalized embedding receive timeouts through `req_http_options`, and
  classified ReqLLM option validation failures as non-retryable configuration
  errors instead of transport outages.

### Changed

- Unified OpenAI, Gemini, OpenRouter, and Ollama with the existing ReqLLM
  bridge, so every hosted provider and Ollama now share one provider runtime.
- Mapped Prism's public `:gemini` adapter to ReqLLM's `:google` provider and
  retained both `GOOGLE_API_KEY` and `GEMINI_API_KEY` credential discovery.
- Added direct-call defaults for balanced generation models and provider
  embedding models while preserving runtime model and base URL overrides.

### Tests

- Replaced duplicate native-provider payload tests with ReqLLM boundary mocks,
  offline provider request-builder contracts, and mocked end-to-end HTTP tests
  for OpenAI Responses, Gemini generation/embeddings, OpenRouter, and Ollama.

## [0.3.2] - 2026-08-20

### Added

- Added one-line bundled provider declarations such as `provider :openai`,
  `provider :anthropic`, and the `:claude`, `:google`, and `:grok` aliases.
- Added ReqLLM-backed provider adapters with configurable fast, balanced, and
  deep profiles.
- Added source-to-target `levels:` mappings so multiple provider catalogs can
  coexist under unique application-owned profile identifiers.
- Added `Spectre.Prism.Adapter.ReqLLM` so applications can wrap any additional
  ReqLLM provider with a small catalog-only adapter.
- Added an optional Bumblebee adapter for application-owned named Nx.Serving
  processes, including opt-in local embeddings.

### Changed

- Updated the package and Stack compatibility contract to Spectre `~> 0.3.2`.
- Updated the package version to `0.3.2` and added ReqLLM 1.20 as the common
  provider runtime. Bumblebee 0.7 remains optional.

### Security

- Preserved runtime-only credentials across ReqLLM adapters and reduced
  upstream failures to sanitized Prism errors while retaining retry-relevant
  HTTP status and stable provider codes.

## [0.3.0] - 2026-08-13

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
- Spectre is resolved directly from the Hex package at `~> 0.3.0`.

### Changed

- Retained GitHub-only distribution with no Hex package metadata.
- Made default Credo analysis part of the required CI quality job.

### Fixed

- Materialized `:agent_default` against the Agent's declared model while
  compiling immutable profiles, satisfying Spectre 0.3's exact selection
  verification for normal calls and bounded fallbacks.
- Contained malformed provider replies, callback failures, selector failures,
  invalid prompt plans, and non-keyword runtime options behind typed errors.
- Preserved HTTP status and retry semantics for non-JSON provider errors and
  validated timeout, redirect, response-size, URL, and header options before a
  request is opened.
- Enforced exact, unique batch embedding indexes, consistent vector dimensions,
  positive configured dimensions, and numeric usage counters.
- Kept the sole available automatic classifier and embedding when unrelated
  providers are registered, while remaining fail-closed when multiple automatic
  candidates are ambiguous.

### Security

- Rejected credentials and live runtime terms recursively from provider
  declarations and adapter catalogs, including alternate credential key forms.
- Blocked URL userinfo, fragments, header injection, unsafe endpoint segments,
  and unbounded provider error codes from compiled or runtime adapter paths.

### Performance

- Replaced repeated list concatenation while compiling provider declarations
  and profiles with linear accumulation and one final reversal.

### Tests

- Added real local-socket HTTP coverage plus malformed transport, catalog,
  provider, embedding, and selector regression suites; project coverage now
  clears the enforced 90% threshold.

## [0.2.0] - 2026-08-01

### Changed

- Aligned the package, inference selector, and Stack contracts with the
  Spectre `0.2.0` GitHub tag.
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

[Unreleased]: https://github.com/elchemista/spectre_prism/compare/v0.3.2...HEAD
[0.3.2]: https://github.com/elchemista/spectre_prism/compare/v0.3.0...v0.3.2
[0.3.0]: https://github.com/elchemista/spectre_prism/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/elchemista/spectre_prism/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/elchemista/spectre_prism/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/elchemista/spectre_prism/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/elchemista/spectre_prism/compare/v0.1.3...v0.1.4
