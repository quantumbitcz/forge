# Deprecations

Items scheduled for removal in future versions.

## Active Deprecations

| Item | Deprecated In | Remove In | Replacement | Reason |
|------|--------------|-----------|-------------|--------|
| `forge-config.md` `sprint.enabled` | 1.11.0 | 2.0.0 | `--sprint` flag on `/forge-run` | Redundant config key; sprint mode is activated via flag |
| `known-deprecations.json` v1 format | 1.10.0 | 2.0.0 | v2 format with `applies_from`/`applies_to` | Version-gated rules require v2 fields |
| `/forge-run --sprint` flag | 1.13.0 | 2.0.0 | `/forge-sprint` skill | Consolidated to dedicated skill for clarity |
| `state.json` v1.4.0 fields without defaults | 1.5.0 | 2.0.0 | Auto-migration at PREFLIGHT | Missing fields get defaults per state-schema.md migration table |

## Removal Policy

- Deprecations are announced at least one minor version before removal
- `<!-- locked -->` fences in `forge-config.md` are never auto-modified
- Framework module deprecations follow `known-deprecations.json` v2 schema
- PREEMPT decay: 10 unused cycles → HIGH→MEDIUM→LOW→ARCHIVED
