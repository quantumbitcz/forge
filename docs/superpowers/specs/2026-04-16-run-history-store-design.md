# Spec 2: Run History Store (SQLite FTS5)

**Status:** Approved
**Author:** Denis Sajnar
**Date:** 2026-04-16
**Depends on:** None (foundation layer)
**Depended on by:** Spec 1 (MCP Server), Spec 3 (Self-Improving Playbooks)

---

## Problem

Forge accumulates valuable pipeline intelligence across runs — findings, learnings, stage timings, convergence patterns, playbook outcomes — but stores it across scattered formats: `forge-log.md` (markdown), `events.jsonl` (append-only log), `playbook-analytics.json` (JSON blob), and `reports/*.md` (per-run markdown). Querying across runs requires parsing multiple file formats and correlating by date. There is no full-text search capability — a developer cannot ask "which runs had authentication-related findings?" without manually grepping through files.

Hermes Agent solves this with a `SessionDB` — SQLite with FTS5 full-text search across all conversations. We adapt this pattern for Forge's pipeline runs.

## Solution

A single SQLite database at `.forge/run-history.db` that provides structured, searchable storage for all pipeline run data. Written by `fg-700-retrospective` at the end of each run. Queried by `forge-insights`, `forge-ask`, `forge-history`, and the MCP server (Spec 1).

## Non-Goals

- **Not replacing `forge-log.md`** — it remains the git-committed institutional memory. The SQLite store is a parallel, structured complement.
- **Not replacing `events.jsonl`** — the event log is a fine-grained audit trail with causal chains. The run history store is an aggregated, queryable summary layer.
- **Not replacing `playbook-analytics.json`** — it stays for backward compat with existing playbook skills. The SQLite store adds cross-run queryability.

## Schema

### Table: `runs`

One row per pipeline execution.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | TEXT | PK | Opaque string matching `state.json.run_id`. Current format: `run-YYYY-MM-DD-{hash}` (set by orchestrator at PREFLIGHT). No format dependency — treat as opaque key. |
| `story_id` | TEXT | NOT NULL | Story/ticket identifier |
| `requirement` | TEXT | NOT NULL | Original requirement text |
| `mode` | TEXT | NOT NULL | Pipeline mode: `standard`, `bugfix`, `migration`, `bootstrap`, `testing`, `refactor`, `performance` |
| `domain_area` | TEXT | | Detected domain (e.g., `auth`, `payments`, `api`) |
| `risk_level` | TEXT | | LOW, MEDIUM, HIGH |
| `started_at` | TEXT | NOT NULL | ISO 8601 with milliseconds |
| `finished_at` | TEXT | | ISO 8601 (NULL if aborted mid-run) |
| `verdict` | TEXT | NOT NULL | PASS, CONCERNS, FAIL, ABORTED |
| `score` | INTEGER | NOT NULL | Final score 0-100 |
| `score_trajectory` | TEXT | | JSON array of per-iteration scores (e.g., `[45, 62, 78, 85]`) |
| `total_iterations` | INTEGER | NOT NULL DEFAULT 1 | Total convergence iterations |
| `wall_time_seconds` | REAL | | Total elapsed time |
| `estimated_cost_usd` | REAL | | Token cost estimate |
| `playbook_id` | TEXT | | Playbook used (NULL if none) |
| `branch_name` | TEXT | | Git branch created |
| `pr_url` | TEXT | | PR URL if shipped |
| `language` | TEXT | | Detected primary language |
| `framework` | TEXT | | Detected framework |
| `config_snapshot` | TEXT | | JSON blob: scoring thresholds, convergence limits, model routing at run time |
| `created_at` | TEXT | NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%f', 'now')) | Row insertion time |

**Index:** `idx_runs_started_at` on `started_at DESC` for time-range queries.
**Index:** `idx_runs_verdict` on `verdict` for filtering.
**Index:** `idx_runs_playbook` on `playbook_id` for playbook analytics.

### Table: `findings`

Every quality finding across all runs.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK AUTOINCREMENT | |
| `run_id` | TEXT | NOT NULL FK → runs(id) ON DELETE CASCADE | |
| `category` | TEXT | NOT NULL | Category code (e.g., `ARCH-HEX-001`, `SEC-AUTH-003`) |
| `severity` | TEXT | NOT NULL | CRITICAL, WARNING, INFO |
| `confidence` | TEXT | NOT NULL DEFAULT 'HIGH' | HIGH, MEDIUM, LOW |
| `file_path` | TEXT | | File where finding was reported |
| `line` | INTEGER | | Line number |
| `message` | TEXT | NOT NULL | Finding description |
| `suggested_fix` | TEXT | | Suggested fix text |
| `agent` | TEXT | NOT NULL | Reviewer agent that emitted it (e.g., `fg-410-code-reviewer`) |
| `resolved` | INTEGER | NOT NULL DEFAULT 0 | 1 if fixed during this run, 0 if persisted |
| `dedup_key` | TEXT | | Deduplication key: `{component}:{file}:{line}:{category}` |

**Index:** `idx_findings_run_id` on `run_id` for per-run lookups.
**Index:** `idx_findings_category` on `category` for recurring finding analysis.
**Index:** `idx_findings_severity` on `severity` for severity filtering.
**Index:** `idx_findings_recurring` on `(category, file_path)` for cross-run recurrence detection.

### Table: `stage_timings`

Per-stage duration and token usage.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK AUTOINCREMENT | |
| `run_id` | TEXT | NOT NULL FK → runs(id) ON DELETE CASCADE | |
| `stage` | TEXT | NOT NULL | PREFLIGHT, EXPLORING, PLANNING, VALIDATING, IMPLEMENTING, VERIFYING, REVIEWING, DOCUMENTING, SHIPPING, LEARNING |
| `agent` | TEXT | NOT NULL | Primary agent for this stage |
| `duration_seconds` | REAL | | Stage wall time |
| `tokens_in` | INTEGER | | Input tokens consumed |
| `tokens_out` | INTEGER | | Output tokens produced |
| `outcome` | TEXT | | Agent outcome (e.g., `completed`, `skipped`, `failed`) |
| `iteration` | INTEGER | NOT NULL DEFAULT 1 | Which convergence iteration this timing is from |

**Index:** `idx_timings_run_id` on `run_id`.
**Index:** `idx_timings_stage` on `stage` for per-stage aggregation.

### Table: `learnings`

PREEMPT items, patterns, tuning extracted per run.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK AUTOINCREMENT | |
| `run_id` | TEXT | NOT NULL FK → runs(id) ON DELETE CASCADE | |
| `type` | TEXT | NOT NULL | PREEMPT, PATTERN, TUNING, PREEMPT_CRITICAL |
| `content` | TEXT | NOT NULL | Learning text |
| `domain` | TEXT | | Domain area (e.g., `auth`, `api`) |
| `confidence` | TEXT | NOT NULL DEFAULT 'MEDIUM' | HIGH, MEDIUM, LOW |
| `source_agent` | TEXT | | Agent that produced the learning |
| `applied_count` | INTEGER | NOT NULL DEFAULT 0 | Times this learning was applied in subsequent runs (incremented by retrospective on each application) |

**Index:** `idx_learnings_run_id` on `run_id`.
**Index:** `idx_learnings_type` on `type`.

### Table: `playbook_runs`

Playbook execution tracking — feeds self-improving playbooks (Spec 3).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK AUTOINCREMENT | |
| `run_id` | TEXT | NOT NULL UNIQUE FK → runs(id) ON DELETE CASCADE | One playbook per run |
| `playbook_id` | TEXT | NOT NULL | Playbook identifier |
| `playbook_version` | TEXT | NOT NULL | Playbook version at time of execution |
| `parameters` | TEXT | | JSON object of parameter values used |
| `score_delta` | INTEGER | | Score minus playbook's historical `avg_score` |
| `stages_skipped` | TEXT | | JSON array of skipped stages |
| `acceptance_results` | TEXT | | JSON: per-criterion pass/fail |
| `refinement_suggestions` | TEXT | | JSON array of suggested refinements (populated by retrospective) |

**Index:** `idx_playbook_runs_playbook_id` on `playbook_id` for per-playbook aggregation.

### Virtual Table: `run_search` (FTS5)

Full-text search across all run data.

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS run_search USING fts5(
    run_id,
    requirement,
    findings_text,
    learnings_text,
    verdict,
    domain_area,
    language,
    framework,
    tokenize='unicode61 remove_diacritics 1'
);
```

**Content type:** Regular content table (not external content). Data is duplicated from source tables into the FTS index. This is intentional — the data is written once per run in a single transaction, so the duplication cost is negligible, and it avoids the trigger maintenance complexity of external content tables.

**Content population:** After inserting run data, concatenate all findings messages and learnings content for that run into `findings_text` and `learnings_text` respectively. This allows queries like `"authentication security"` to match runs where those terms appear in any finding or learning.

**FTS5 insert:** One row per run, written in the same transaction as all other tables.

## Write Path

`fg-700-retrospective` already gathers all necessary data during its 12-step execution. The run history write is added as a new step between step 10 (consolidation) and step 11 (summary).

### Step: Write Run History

```
1. Open .forge/run-history.db (create + apply schema if absent)
2. BEGIN TRANSACTION
3. INSERT INTO runs (from state.json fields)
4. INSERT INTO findings (from quality gate structured output)
5. INSERT INTO stage_timings (from state.json.tokens per-stage breakdown)
6. INSERT INTO learnings (from extracted PREEMPT/PATTERN/TUNING items)
7. IF playbook was used:
     INSERT INTO playbook_runs (from state.json.playbook_id + analytics)
8. INSERT INTO run_search (concatenated text for FTS)
9. UPDATE applied_count: For each PREEMPT/PATTERN applied in this run,
     UPDATE learnings SET applied_count = applied_count + 1
     WHERE type IN ('PREEMPT', 'PATTERN') AND content = {applied_item_content}
10. COMMIT
11. Run retention cleanup: DELETE FROM runs WHERE started_at < datetime('now', '-{retention_days} days')
12. PRAGMA optimize (periodic — every 10th run)
```

All writes in a single transaction — atomic, no partial state on crash.

### Data Sources for Each Table

| Table | Source | How Gathered |
|-------|--------|-------------|
| `runs` | `state.json` root fields | Already loaded by retrospective at step 1 |
| `findings` | Quality gate structured output `<!-- FORGE_STRUCTURED_OUTPUT {...} -->` | Already parsed by retrospective at step 2 |
| `stage_timings` | `state.json.tokens` per-stage breakdown | Already loaded at step 1 |
| `learnings` | Extracted during retrospective steps 4-6 | In-memory during retrospective execution |
| `playbook_runs` | `state.json.playbook_id` + `playbook-analytics.json` | Already loaded at step 2 |

No new data gathering needed — the retrospective already has everything.

## Read Path

### Consumers

| Consumer | Query Pattern | Purpose |
|----------|--------------|---------|
| `forge-insights` | Aggregates: `AVG(score)`, `COUNT(*) GROUP BY verdict`, time-series | Replace markdown/JSON parsing with SQL |
| `forge-ask` | FTS5 `MATCH` on `run_search` | Natural language questions about past runs |
| `forge-history` | `SELECT * FROM runs ORDER BY started_at DESC LIMIT N` | List recent runs |
| MCP server | All of the above via Python `sqlite3` | Cross-platform query access |
| `fg-700-retrospective` | `SELECT category, COUNT(*) FROM findings GROUP BY category HAVING COUNT(*) >= 3` | Recurring finding detection for PREEMPT promotion |

### Query via `sqlite3` CLI

All existing skills (bash-based) query via `sqlite3` CLI commands:

```bash
sqlite3 -json .forge/run-history.db "SELECT id, score, verdict FROM runs ORDER BY started_at DESC LIMIT 10"
```

The MCP server (Python) uses the `sqlite3` stdlib module directly.

## Schema Versioning

The database includes a `schema_version` pragma for future migrations:

```sql
PRAGMA user_version = 1;
```

On open, the retrospective checks `PRAGMA user_version`:
- If 0 (new database): apply full schema, set to current version
- If current: proceed
- If older: apply incremental migrations (ALTER TABLE, new indexes)
- If newer: log WARNING, proceed read-only (forward compat — newer Forge wrote it)

Migration scripts live in `shared/run-history/migrations/` as numbered SQL files: `001-initial.sql`, `002-add-column.sql`, etc. This directory is owned by the run history store (Spec 2), not the MCP server — the MCP server reads this database but does not own its schema.

## Configuration

New section in `forge-config.md`:

```yaml
run_history:
  enabled: true                # Master switch
  retention_days: 365          # Delete runs older than this
  optimize_interval: 10        # PRAGMA optimize every N runs
```

## File Locations

| File | Purpose |
|------|---------|
| `.forge/run-history.db` | SQLite database (gitignored, survives `/forge-reset`) |
| `shared/run-history/migrations/001-initial.sql` | Schema DDL |
| `shared/run-history/run-history.md` | Schema reference + query cookbook |
| `agents/fg-700-retrospective.md` | Modified: add run history write step |
| `shared/state-schema.md` | Modified: add `run-history.db` to `.forge/` directory layout and survival list |
| `shared/run-history/run-history.md` | New: schema reference + query cookbook |

### Exact `state-schema.md` Modifications

**Directory structure entry:**
```
├── run-history.db                       # Pipeline run history (SQLite FTS5, survives /forge-reset)
```

**File lifecycle table row:**
```
| run-history.db | Stage 9 (LEARN) | fg-700-retrospective | Yes (survives /forge-reset) | No |
```

## Survival & Lifecycle

- **Survives `/forge-reset`:** Yes — same as `explore-cache.json`, `events.jsonl`, `wiki/`
- **Survives `rm -rf .forge/`:** No — recreated from scratch on next run
- **Backfill from `forge-log.md`:** Not implemented. New runs populate forward. Historical data stays in `forge-log.md`.
- **Concurrent access:** Single-writer (one pipeline at a time per `.forge/.lock`). Multiple readers safe (SQLite WAL mode).

## WAL Mode

The database opens with:

```sql
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
```

WAL mode allows concurrent reads during writes and improves crash resilience. The 5-second busy timeout handles the edge case where the MCP server reads while the retrospective writes.

## Error Handling

- **`sqlite3` CLI unavailable:** Log WARNING at PREFLIGHT, set `run_history.enabled: false` for this run. Pipeline continues without run history.
- **Database locked:** Retry once after 100ms (handled by `busy_timeout`). If still locked, skip write, log WARNING.
- **Schema migration fails:** Log CRITICAL, do not write, do not corrupt existing data. Pipeline continues.
- **Disk full:** SQLite returns `SQLITE_FULL`. Log CRITICAL, skip write. Suggest running retention cleanup.

## Testing

- Structural test: verify `shared/run-history/migrations/001-initial.sql` is valid SQL (parse with `sqlite3 :memory:`)
- Structural test: verify `run-history.db` is in the `.forge/` survival list in `state-schema.md`
- Contract test: verify `fg-700-retrospective.md` references run history write step
- Scenario test: create in-memory DB, insert sample run, query FTS5, verify results
