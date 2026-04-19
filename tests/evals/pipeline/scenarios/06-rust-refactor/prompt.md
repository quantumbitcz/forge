# Scenario 06 — Rust trait extraction

Three struct impls (`JsonFormatter`, `YamlFormatter`, `TomlFormatter`) share the same public surface. Extract a `Formatter` trait, move shared logic to a default method, and update callers. Existing `tests/` must continue to pass.

Pipeline mode: `standard` (refactor overlay).
