# Convention Composition Order

When the orchestrator resolves the convention stack for a component at PREFLIGHT, it loads convention files in this order. Later files override earlier ones for conflicting rules. All files contribute additively for non-conflicting rules.

## Resolution Order (most specific wins)

1. **Testing module** (`modules/testing/{name}.md`) -- test framework conventions
2. **Generic layer** (`modules/{layer}/{name}.md`) -- cross-cutting domain conventions (auth, observability, etc.)
3. **Code quality** (`modules/code-quality/{tool}.md`) -- linter/formatter conventions
4. **Language** (`modules/languages/{lang}.md`) -- language-level conventions
5. **Framework** (`modules/frameworks/{name}/conventions.md`) -- framework base conventions
6. **Framework binding** (`modules/frameworks/{name}/{layer}/{binding}.md`) -- framework-specific layer binding (e.g., spring/persistence/hibernate.md)
7. **Variant** (`modules/frameworks/{name}/variants/{variant}.md`) -- variant-specific overrides

Files loaded later (higher number) take precedence for conflicting rules. Example: if the language module says "use camelCase" but the framework variant says "use snake_case for database columns," the variant wins.

## Soft Cap

Convention stacks are soft-capped at 12 files per component. Beyond 12, the orchestrator logs WARNING and loads the 12 most specific files (prioritizing variant and framework binding). Module overviews are capped at 15 lines each.

## Drift Detection

Mid-run SHA256 hash comparison detects if convention files change during a pipeline run. Agents react only to changes in their relevant section (determined by the agent's `focus` field). Per-section hashes are stored in `state.json.conventions_section_hashes` (single-component) or `state.json.components[key].conventions_section_hashes` (multi-component).

## Convention Stack in State

The resolved convention stack is recorded in `state.json.components[key].convention_stack` as an ordered array of file paths. This enables:
- Reproducible builds (same conventions produce same results)
- Drift detection (hash comparison against stored stack)
- Debugging (inspect which files contributed to the active conventions)
