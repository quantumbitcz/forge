# Deprecations

Items scheduled for removal in future versions.

## Active Deprecations

| Item | Deprecated In | Remove In | Replacement | Reason |
|------|--------------|-----------|-------------|--------|
| `forge-config.md` `sprint.enabled` | 1.11.0 | 2.0.0 | `--sprint` flag on `/forge-run` | Redundant config key; sprint mode is activated via flag |
| `known-deprecations.json` v1 format | 1.10.0 | 2.0.0 | v2 format with `applies_from`/`applies_to` | Version-gated rules require v2 fields |
| `/forge-run --sprint` flag | 1.13.0 | 2.0.0 | `/forge-sprint` skill | Consolidated to dedicated skill for clarity |
| `state.json` v1.4.0 fields without defaults | 1.5.0 | 2.0.0 | Auto-migration at PREFLIGHT | Missing fields get defaults per state-schema.md migration table |

## Migration Examples

### `sprint.enabled` (deprecated in 1.11.0, remove in 2.0.0)

**Before (deprecated):**
```yaml
sprint:
  enabled: true
  max_parallel: 3
```

**After (replacement):**
```yaml
# sprint.enabled is no longer needed -- sprint mode is activated by /forge-sprint invocation
sprint:
  max_parallel: 3
```

**Migration:** Remove the `enabled:` line. Sprint mode is now activated by skill invocation (`/forge-sprint`) or `--sprint` flag, not config flag.

### `known-deprecations.json` v1 format (deprecated in 1.10.0, remove in 2.0.0)

**Before (v1):**
```json
{
  "deprecations": [
    { "pattern": "ReactDOM.render", "replacement": "createRoot().render()", "package": "react-dom", "since": "18.0.0" }
  ]
}
```

**After (v2):**
```json
{
  "version": 2,
  "last_refreshed": "2026-04-14",
  "deprecations": [
    { "pattern": "ReactDOM.render", "replacement": "createRoot().render()", "package": "react-dom", "since": "18.0.0", "applies_from": "18.0.0", "applies_to": "*", "added": "2026-04-14", "addedBy": "seed" }
  ]
}
```

**Migration:** Add `"version": 2`, `"last_refreshed"` to root. Add `applies_from`, `applies_to`, `added`, `addedBy` to each entry.

### `/forge-run --sprint` flag (deprecated in 1.13.0, remove in 2.0.0)

**Before (deprecated):**
```bash
/forge-run --sprint "Build feature X"
```

**After (replacement):**
```bash
/forge-sprint "Build feature X"
```

**Migration:** Replace `/forge-run --sprint` with `/forge-sprint`. The dedicated skill provides the same behavior with additional parallel dispatch control.

### `state.json` v1.4.0 fields without defaults (deprecated in 1.5.0, remove in 2.0.0)

**Before (v1.4.0):**
```json
{ "version": "1.4.0", "story_state": "IMPLEMENTING" }
```

**After (v1.5.0+):**
```json
{ "version": "1.5.0", "story_state": "IMPLEMENTING", "_seq": 0, "previous_state": null, "convergence": { "diminishing_count": 0 } }
```

**Migration:** Automatic at PREFLIGHT. Missing fields are added with defaults per `state-schema.md` migration table. No manual action required.

## Removal Policy

- Deprecations are announced at least one minor version before removal
- `<!-- locked -->` fences in `forge-config.md` are never auto-modified
- Framework module deprecations follow `known-deprecations.json` v2 schema
- PREEMPT decay: 10 unused cycles → HIGH→MEDIUM→LOW→ARCHIVED
