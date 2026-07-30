# Changelog

All notable changes to Spectre Prism are documented in this file.

## [Unreleased]

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

[Unreleased]: https://github.com/elchemista/spectre_prism/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/elchemista/spectre_prism/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/elchemista/spectre_prism/compare/v0.1.3...v0.1.4
