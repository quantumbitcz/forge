# Explore Cache

Persists codebase exploration data across pipeline runs in `.forge/explore-cache.json`. On subsequent runs, only files changed since the last explored commit SHA are re-analyzed.

## Cache Schema

`.forge/explore-cache.json`:

```json
{
  "schema_version": "1.0.0",
  "last_explored_sha": "abc123def456",
  "conventions_hash": "ab12cd34",
  "file_index": {
    "src/domain/Plan.kt": {
      "hash": "sha256:...",
      "patterns": ["repository", "entity", "domain-object"],
      "dependencies": ["PlanRepository", "PlanService"],
      "module": "domain"
    }
  },
  "cache_age_runs": 3,
  "created_at": "2026-04-10T10:00:00Z",
  "last_updated_at": "2026-04-12T10:00:00Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Cache format version for migration |
| `last_explored_sha` | string | Git commit SHA of last full/partial explore |
| `conventions_hash` | string | SHA256 of `forge-config.md` conventions section at time of explore |
| `file_index` | object | Per-file exploration data keyed by project-relative path |
| `file_index.*.hash` | string | SHA256 of file content at time of indexing |
| `file_index.*.patterns` | string[] | Detected code patterns (entity, repository, controller, service, etc.) |
| `file_index.*.dependencies` | string[] | Key symbols this file depends on or exports |
| `file_index.*.module` | string | Detected module/layer (domain, infrastructure, api, etc.) |
| `cache_age_runs` | integer | Number of runs since last full re-explore |
| `created_at` | string | ISO 8601 timestamp of initial creation |
| `last_updated_at` | string | ISO 8601 timestamp of last update |

## Invalidation Rules

| Condition | Action |
|-----------|--------|
| `cache_age_runs > max_cache_age_runs` (config, default 10) | Full re-explore |
| `conventions_hash` differs from current `forge-config.md` hash | Full re-explore |
| Cache file missing or corrupt (invalid JSON, missing `schema_version`) | Full re-explore |
| `schema_version` mismatch with expected cache schema version (currently 1.0.0) | Full re-explore |
| `--full-explore` flag passed to `/forge-run` | Full re-explore |
| None of the above | Partial re-explore (changed files only) |

## Partial Re-Explore

When cache is valid:
1. Compute changed files: `git diff --name-only {last_explored_sha}..HEAD`
2. For each changed file: re-analyze and update `file_index` entry
3. For deleted files: remove from `file_index`
4. For new files: add to `file_index`
5. Update `last_explored_sha` to current HEAD
6. Increment `cache_age_runs`
7. Update `last_updated_at`

The EXPLORE stage agent receives the cached `file_index` as context, plus the list of changed files to focus on.

## PREFLIGHT Integration

At PREFLIGHT, the orchestrator:
1. Checks if `.forge/explore-cache.json` exists
2. If exists: validates schema, checks invalidation rules
3. If valid: passes cache data to EXPLORE dispatch prompt with instruction to do partial analysis
4. If invalid or missing: normal full EXPLORE (agent creates cache at completion)
5. Records cache status in `stage_0_notes`: "Explore cache: hit (12 changed files) / miss (full explore) / stale (conventions changed)"

## Configuration

In `forge-config.md`:

    explore:
      cache_enabled: true
      max_cache_age_runs: 10

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| `cache_enabled` | boolean | `true` | Enable/disable explore caching |
| `max_cache_age_runs` | 1-50 | 10 | Runs before forced full re-explore |

## /forge-recover reset Behavior

`/forge-recover reset` preserves `explore-cache.json` (same as `docs-index.json` and `feedback/`). Only `/forge-recover reset --hard` or manual deletion removes it.
