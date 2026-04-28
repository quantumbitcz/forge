# Run History Store

## Overview

Structured, searchable pipeline run history for trend analysis, playbook refinement, and learning promotion.

- **Location:** `.forge/run-history.db` (SQLite)
- **Written by:** `fg-700-retrospective` (Stage 9 LEARN)
- **Lifecycle:** Survives `/forge-admin recover reset` (same as `explore-cache.json`). Only `rm -rf .forge/` removes it.
- **Schema version:** 1 (`PRAGMA user_version=1`)
- **FTS5 engine:** `run_search` virtual table with `unicode61` tokenizer

## Table Reference

| Table | Purpose |
|-------|---------|
| `runs` | One row per pipeline run. Core metadata: mode, verdict, score, timing, cost, language/framework, config snapshot. |
| `findings` | Individual reviewer findings from each run. Linked to `runs` via `run_id`. Supports recurrence analysis across runs. |
| `stage_timings` | Per-stage duration and token usage. Enables hotspot analysis and cost breakdown by agent. |
| `learnings` | PREEMPT rules and patterns extracted during LEARN. Tracks `applied_count` across runs for promotion decisions. |
| `playbook_runs` | Playbook-specific metadata for runs that used a playbook: version, parameters, score delta, skipped stages, acceptance results, refinement suggestions. |
| `run_search` | FTS5 virtual table. Full-text index over requirement, findings, learnings, verdict, domain, language, framework. Query with `MATCH`. |

## FTS5 Usage

The `run_search` table uses the `unicode61` tokenizer with `remove_diacritics 1`. Query syntax:

```sql
-- Simple keyword match
SELECT run_id FROM run_search WHERE run_search MATCH 'authentication';

-- Phrase match
SELECT run_id FROM run_search WHERE run_search MATCH '"rate limiting"';

-- Column-scoped match
SELECT run_id FROM run_search WHERE run_search MATCH 'findings_text:SEC-AUTH';

-- Snippet extraction (column index 2 = findings_text)
SELECT run_id,
       snippet(run_search, 2, '**', '**', '...', 20) AS snippet
FROM run_search
WHERE run_search MATCH 'authentication';

-- Ranked by relevance (BM25)
SELECT run_id, bm25(run_search) AS rank
FROM run_search
WHERE run_search MATCH 'timeout'
ORDER BY rank;
```

Column index map for `snippet()` / `highlight()`:

| Index | Column |
|-------|--------|
| 0 | run_id |
| 1 | requirement |
| 2 | findings_text |
| 3 | learnings_text |
| 4 | verdict |
| 5 | domain_area |
| 6 | language |
| 7 | framework |

## Query Cookbook

### List recent runs

```sql
SELECT id, score, verdict FROM runs ORDER BY started_at DESC LIMIT 10;
```

### Search runs by text

```sql
SELECT run_id, snippet(run_search, 2, '**', '**', '...', 20) as snippet
FROM run_search
WHERE run_search MATCH 'authentication'
LIMIT 10;
```

### Recurring findings

```sql
SELECT category, COUNT(*) as cnt
FROM findings
GROUP BY category
HAVING cnt >= 3
ORDER BY cnt DESC;
```

### Playbook success rate

```sql
SELECT playbook_id,
       COUNT(*) as total,
       SUM(CASE WHEN r.verdict='PASS' THEN 1 ELSE 0 END) as passed
FROM playbook_runs pr
JOIN runs r ON pr.run_id = r.id
GROUP BY playbook_id;
```

### Update applied_count

```sql
UPDATE learnings
SET applied_count = applied_count + 1
WHERE type IN ('PREEMPT','PATTERN') AND content = ?;
```

### Average score by framework

```sql
SELECT framework, AVG(score) as avg_score, COUNT(*) as runs
FROM runs
WHERE framework IS NOT NULL
GROUP BY framework
ORDER BY avg_score DESC;
```

### Stage hotspots (slowest stages)

```sql
SELECT stage, AVG(duration_seconds) as avg_seconds, SUM(tokens_in + tokens_out) as total_tokens
FROM stage_timings
GROUP BY stage
ORDER BY avg_seconds DESC;
```

### Runs exceeding cost threshold

```sql
SELECT id, requirement, estimated_cost_usd, score, verdict
FROM runs
WHERE estimated_cost_usd > 0.50
ORDER BY estimated_cost_usd DESC;
```

## Configuration

Configured in `forge-config.md` under `run_history:`:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `run_history.enabled` | boolean | `true` | Enable/disable run history recording |
| `run_history.retention_days` | integer | `365` | Delete runs older than N days (valid: 30-3650) |
| `run_history.optimize_interval` | integer | `10` | Run `PRAGMA optimize` every N runs |

Example:

```yaml
run_history:
  enabled: true
  retention_days: 365
  optimize_interval: 10
```

## Schema Versioning

The `PRAGMA user_version` field tracks the schema version. Migration files live in `shared/run-history/migrations/`:

| File | Version | Description |
|------|---------|-------------|
| `001-initial.sql` | 1 | Initial schema: runs, findings, stage_timings, learnings, playbook_runs, run_search FTS5 |
| `002-feature-usage.sql` | 2 | feature_usage table for feature activation tracking |
| `003-cost-columns.sql` | 3 | Phase 6 cost governance columns on `runs`: ceiling_usd, spent_usd, ceiling_breaches, throttle_events |

Migration strategy: `fg-700-retrospective` checks `PRAGMA user_version` on DB open. If version < expected, applies pending migration files in numeric order. Migrations are gated by `user_version` and applied at most once. Each migration's SQL is intended to be idempotent where supported (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`); migration 003 uses `ALTER TABLE … ADD COLUMN` which SQLite does not support `IF NOT EXISTS` on — idempotency for 003 is enforced by the user_version gate alone.

### Phase 6 cost columns (migration 003)

Plan referenced "run_summary"; actual table is `runs` (per `001-initial.sql`). Migration 003 adds the four cost-governance columns to that table.

| Column | Type | Default | Meaning |
|---|---|---|---|
| `ceiling_usd` | REAL | 0.0 | Configured `cost.ceiling_usd` at run start |
| `spent_usd` | REAL | 0.0 | Final `state.cost.spent_usd` |
| `ceiling_breaches` | INTEGER | 0 | Count of `.forge/cost-incidents/*.json` written |
| `throttle_events` | INTEGER | 0 | `len(state.cost.throttle_events)` |

Indexes: `idx_runs_spent_usd`, `idx_runs_breaches` (partial, non-zero only).

## Error Handling

| Condition | Behaviour |
|-----------|-----------|
| `sqlite3` not found | Log WARNING, skip run history write, continue pipeline |
| DB locked (busy timeout 5000ms) | Log WARNING with run ID, skip write, continue pipeline |
| Disk full | Log CRITICAL finding `INFRA-DISK-FULL`, skip write, continue pipeline |
| Corrupt DB | Log WARNING, attempt `PRAGMA integrity_check`, if fails rename to `.forge/run-history.db.corrupt-{epoch}` and create fresh DB |
| FTS5 not compiled | Log WARNING, skip `run_search` population, structured queries still work |
