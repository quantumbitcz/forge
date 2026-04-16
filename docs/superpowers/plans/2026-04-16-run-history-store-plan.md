# Run History Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a SQLite FTS5 database at `.forge/run-history.db` that stores structured, searchable pipeline run data written by the retrospective agent.

**Architecture:** Single SQLite database with 5 tables + 1 FTS5 virtual table. Written by `fg-700-retrospective` in a single transaction per run. Queried by existing skills and the MCP server (Spec 1). Schema DDL in `shared/run-history/migrations/001-initial.sql`. Reference docs in `shared/run-history/run-history.md`.

**Tech Stack:** SQLite (WAL mode, FTS5), bash (bats tests)

**Spec:** `docs/superpowers/specs/2026-04-16-run-history-store-design.md`

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `shared/run-history/migrations/001-initial.sql` | Schema DDL |
| Create | `shared/run-history/run-history.md` | Schema reference + query cookbook |
| Modify | `agents/fg-700-retrospective.md` | Add run history write step |
| Modify | `shared/state-schema.md` | Add `run-history.db` to directory layout + lifecycle table |
| Create | `tests/contract/run-history-schema.bats` | Contract tests for schema and integration |
| Modify | `shared/preflight-constraints.md` | Add `run_history.*` config validation |
| Modify | `CLAUDE.md` | Add run history to feature table and `.forge/` survival list |

---

### Task 1: Create Schema DDL

**Files:**
- Create: `shared/run-history/migrations/001-initial.sql`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p shared/run-history/migrations
```

- [ ] **Step 2: Write the schema DDL**

Create `shared/run-history/migrations/001-initial.sql` with the full schema:

```sql
-- Run History Store Schema v1
-- Location: .forge/run-history.db
-- Written by: fg-700-retrospective (Stage 9 LEARN)
-- Survives: /forge-reset (same as explore-cache.json)

PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=5000;
PRAGMA user_version=1;

-- One row per pipeline execution
CREATE TABLE IF NOT EXISTS runs (
    id              TEXT    PRIMARY KEY,  -- Opaque string from state.json.run_id
    story_id        TEXT    NOT NULL,
    requirement     TEXT    NOT NULL,
    mode            TEXT    NOT NULL,     -- standard|bugfix|migration|bootstrap|testing|refactor|performance
    domain_area     TEXT,
    risk_level      TEXT,                 -- LOW|MEDIUM|HIGH
    started_at      TEXT    NOT NULL,     -- ISO 8601
    finished_at     TEXT,
    verdict         TEXT    NOT NULL,     -- PASS|CONCERNS|FAIL|ABORTED
    score           INTEGER NOT NULL,
    score_trajectory TEXT,                -- JSON array of per-iteration scores
    total_iterations INTEGER NOT NULL DEFAULT 1,
    wall_time_seconds REAL,
    estimated_cost_usd REAL,
    playbook_id     TEXT,
    branch_name     TEXT,
    pr_url          TEXT,
    language        TEXT,
    framework       TEXT,
    config_snapshot TEXT,                 -- JSON: scoring/convergence config at run time
    created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%f', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_runs_started_at ON runs(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_runs_verdict ON runs(verdict);
CREATE INDEX IF NOT EXISTS idx_runs_playbook ON runs(playbook_id);

-- Quality findings across all runs
CREATE TABLE IF NOT EXISTS findings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id      TEXT    NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    category    TEXT    NOT NULL,
    severity    TEXT    NOT NULL,         -- CRITICAL|WARNING|INFO
    confidence  TEXT    NOT NULL DEFAULT 'HIGH',
    file_path   TEXT,
    line        INTEGER,
    message     TEXT    NOT NULL,
    suggested_fix TEXT,
    agent       TEXT    NOT NULL,
    resolved    INTEGER NOT NULL DEFAULT 0,
    dedup_key   TEXT
);

CREATE INDEX IF NOT EXISTS idx_findings_run_id ON findings(run_id);
CREATE INDEX IF NOT EXISTS idx_findings_category ON findings(category);
CREATE INDEX IF NOT EXISTS idx_findings_severity ON findings(severity);
CREATE INDEX IF NOT EXISTS idx_findings_recurring ON findings(category, file_path);

-- Per-stage duration and token usage
CREATE TABLE IF NOT EXISTS stage_timings (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id          TEXT    NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    stage           TEXT    NOT NULL,
    agent           TEXT    NOT NULL,
    duration_seconds REAL,
    tokens_in       INTEGER,
    tokens_out      INTEGER,
    outcome         TEXT,
    iteration       INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_timings_run_id ON stage_timings(run_id);
CREATE INDEX IF NOT EXISTS idx_timings_stage ON stage_timings(stage);

-- Extracted learnings per run
CREATE TABLE IF NOT EXISTS learnings (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id          TEXT    NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    type            TEXT    NOT NULL,     -- PREEMPT|PATTERN|TUNING|PREEMPT_CRITICAL
    content         TEXT    NOT NULL,
    domain          TEXT,
    confidence      TEXT    NOT NULL DEFAULT 'MEDIUM',
    source_agent    TEXT,
    applied_count   INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_learnings_run_id ON learnings(run_id);
CREATE INDEX IF NOT EXISTS idx_learnings_type ON learnings(type);

-- Playbook execution tracking
CREATE TABLE IF NOT EXISTS playbook_runs (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id                  TEXT    NOT NULL UNIQUE REFERENCES runs(id) ON DELETE CASCADE,
    playbook_id             TEXT    NOT NULL,
    playbook_version        TEXT    NOT NULL,
    parameters              TEXT,          -- JSON object
    score_delta             INTEGER,
    stages_skipped          TEXT,          -- JSON array
    acceptance_results      TEXT,          -- JSON: per-criterion pass/fail
    refinement_suggestions  TEXT           -- JSON array (populated by retrospective)
);

CREATE INDEX IF NOT EXISTS idx_playbook_runs_playbook_id ON playbook_runs(playbook_id);

-- FTS5 full-text search (regular content table — data duplicated, no trigger maintenance)
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

- [ ] **Step 3: Validate the SQL is parseable**

```bash
sqlite3 :memory: < shared/run-history/migrations/001-initial.sql
echo $?  # Expected: 0
```

- [ ] **Step 4: Commit**

```bash
git add shared/run-history/
git commit -m "feat(run-history): add schema DDL for pipeline run history store"
```

---

### Task 2: Create Schema Reference Document

**Files:**
- Create: `shared/run-history/run-history.md`

- [ ] **Step 1: Write the schema reference**

Create `shared/run-history/run-history.md` with table descriptions, query cookbook, and configuration reference. Include:
- Overview (purpose, location, lifecycle)
- Table reference (columns, types, constraints for each table)
- FTS5 usage guide (MATCH syntax, snippet(), rank)
- Query cookbook with examples:
  - List recent runs: `SELECT id, score, verdict FROM runs ORDER BY started_at DESC LIMIT 10`
  - Search runs: `SELECT run_id, snippet(run_search, 2, '<b>', '</b>', '...', 20) FROM run_search WHERE run_search MATCH 'authentication' LIMIT 10`
  - Recurring findings: `SELECT category, COUNT(*) as cnt FROM findings GROUP BY category HAVING cnt >= 3 ORDER BY cnt DESC`
  - Per-playbook success rate: `SELECT playbook_id, COUNT(*) as total, SUM(CASE WHEN r.verdict='PASS' THEN 1 ELSE 0 END) as passed FROM playbook_runs pr JOIN runs r ON pr.run_id = r.id GROUP BY playbook_id`
  - Update applied_count: `UPDATE learnings SET applied_count = applied_count + 1 WHERE type IN ('PREEMPT','PATTERN') AND content = ?`
- Configuration section (`run_history.*` keys)
- Schema versioning (PRAGMA user_version, migration strategy)
- Error handling (missing sqlite3, locked DB, disk full)

- [ ] **Step 2: Commit**

```bash
git add shared/run-history/run-history.md
git commit -m "docs(run-history): add schema reference and query cookbook"
```

---

### Task 3: Update State Schema

**Files:**
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Add `run-history.db` to the directory structure**

In the `.forge/` directory structure block (after the `trust.json` line, before `+-- reports/`), add:

```
+-- run-history.db                       # Pipeline run history — SQLite FTS5 (survives /forge-reset)
+-- playbook-refinements/                # Playbook improvement proposals (survives /forge-reset)
```

- [ ] **Step 2: Add to the File Lifecycle table**

After the `playbook-analytics.json` row, add:

```
| `run-history.db` | Stage 9 (LEARN) | `fg-700-retrospective` | Yes (survives /forge-reset) | No |
| `playbook-refinements/` | Stage 9 (LEARN) | `fg-700-retrospective` | Yes (survives /forge-reset) | No |
```

- [ ] **Step 3: Commit**

```bash
git add shared/state-schema.md
git commit -m "docs(state-schema): add run-history.db and playbook-refinements to .forge/ layout"
```

---

### Task 4: Update Retrospective Agent

**Files:**
- Modify: `agents/fg-700-retrospective.md`

- [ ] **Step 1: Add run history write step**

In the `## 3. Three Outputs` section, after Output 2 (Configuration Updates) and before Output 3 (Improvement Proposals), add a new output section:

```markdown
### Output 2.5: Run History Store

Write structured run data to `.forge/run-history.db` for cross-run queryability. Schema: `shared/run-history/run-history.md`.

**Steps:**
1. Open `.forge/run-history.db` (if absent, create and apply `shared/run-history/migrations/001-initial.sql`)
2. Check `PRAGMA user_version` — if 0, apply schema; if current, proceed; if older, apply migrations
3. BEGIN TRANSACTION
4. INSERT INTO `runs` from `state.json` root fields
5. INSERT INTO `findings` from quality gate structured output (`<!-- FORGE_STRUCTURED_OUTPUT -->`)
6. INSERT INTO `stage_timings` from `state.json.tokens` per-stage breakdown
7. INSERT INTO `learnings` from extracted PREEMPT/PATTERN/TUNING items (this run)
8. IF `state.json.playbook_id` is set: INSERT INTO `playbook_runs`
9. INSERT INTO `run_search` (concatenate requirement + all finding messages + all learning content)
10. UPDATE `learnings SET applied_count = applied_count + 1` for each PREEMPT/PATTERN applied in this run
11. COMMIT
12. DELETE FROM `runs` WHERE `started_at < datetime('now', '-{run_history.retention_days} days')`
13. Every 10th run: `PRAGMA optimize`

**Error handling:** If `sqlite3` CLI unavailable, log WARNING and skip. If DB locked after busy_timeout, skip write and log WARNING. If schema migration fails, do not write, log CRITICAL. Pipeline continues regardless.

**Config:** `run_history.enabled` (default true), `run_history.retention_days` (default 365), `run_history.optimize_interval` (default 10).
```

- [ ] **Step 2: Add run-history.db to the Context Budget section**

In `## 2. Context Budget`, add `.forge/run-history.db` to the Read list.

- [ ] **Step 3: Commit**

```bash
git add agents/fg-700-retrospective.md
git commit -m "feat(retrospective): add run history store write step"
```

---

### Task 5: Add Config Validation

**Files:**
- Modify: `shared/preflight-constraints.md`

- [ ] **Step 1: Add `run_history.*` validation rules**

In the PREFLIGHT constraints document, add a new section:

```markdown
### Run History Store

| Field | Type | Default | Valid Range | Validation |
|-------|------|---------|-------------|------------|
| `run_history.enabled` | boolean | `true` | true/false | — |
| `run_history.retention_days` | integer | `365` | 30-3650 | WARN if <90 (losing trend data) |
| `run_history.optimize_interval` | integer | `10` | 1-100 | — |
```

- [ ] **Step 2: Commit**

```bash
git add shared/preflight-constraints.md
git commit -m "docs(preflight): add run_history config validation rules"
```

---

### Task 6: Write Contract Tests

**Files:**
- Create: `tests/contract/run-history-schema.bats`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bats
# Contract tests: run history store schema and integration points.

load '../helpers/test-helpers'

SCHEMA_FILE="$PLUGIN_ROOT/shared/run-history/migrations/001-initial.sql"
REFERENCE_DOC="$PLUGIN_ROOT/shared/run-history/run-history.md"
RETROSPECTIVE="$PLUGIN_ROOT/agents/fg-700-retrospective.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
PREFLIGHT="$PLUGIN_ROOT/shared/preflight-constraints.md"

# ---------------------------------------------------------------------------
# 1. Schema file exists and is valid SQL
# ---------------------------------------------------------------------------
@test "run-history: schema DDL exists" {
  [[ -f "$SCHEMA_FILE" ]]
}

@test "run-history: schema DDL is valid SQL" {
  if ! command -v sqlite3 &>/dev/null; then
    skip "sqlite3 not available"
  fi
  sqlite3 :memory: < "$SCHEMA_FILE"
}

# ---------------------------------------------------------------------------
# 2. All required tables present in schema
# ---------------------------------------------------------------------------
@test "run-history: schema creates runs table" {
  grep -q "CREATE TABLE.*runs" "$SCHEMA_FILE" \
    || fail "runs table not found in schema"
}

@test "run-history: schema creates findings table" {
  grep -q "CREATE TABLE.*findings" "$SCHEMA_FILE" \
    || fail "findings table not found in schema"
}

@test "run-history: schema creates stage_timings table" {
  grep -q "CREATE TABLE.*stage_timings" "$SCHEMA_FILE" \
    || fail "stage_timings table not found in schema"
}

@test "run-history: schema creates learnings table" {
  grep -q "CREATE TABLE.*learnings" "$SCHEMA_FILE" \
    || fail "learnings table not found in schema"
}

@test "run-history: schema creates playbook_runs table" {
  grep -q "CREATE TABLE.*playbook_runs" "$SCHEMA_FILE" \
    || fail "playbook_runs table not found in schema"
}

@test "run-history: schema creates FTS5 run_search virtual table" {
  grep -q "CREATE VIRTUAL TABLE.*run_search.*fts5" "$SCHEMA_FILE" \
    || fail "run_search FTS5 virtual table not found in schema"
}

# ---------------------------------------------------------------------------
# 3. WAL mode and user_version set
# ---------------------------------------------------------------------------
@test "run-history: schema sets WAL journal mode" {
  grep -q "PRAGMA journal_mode=WAL" "$SCHEMA_FILE" \
    || fail "WAL mode not set in schema"
}

@test "run-history: schema sets user_version" {
  grep -q "PRAGMA user_version=" "$SCHEMA_FILE" \
    || fail "user_version pragma not found"
}

# ---------------------------------------------------------------------------
# 4. Reference document exists
# ---------------------------------------------------------------------------
@test "run-history: reference document exists" {
  [[ -f "$REFERENCE_DOC" ]]
}

# ---------------------------------------------------------------------------
# 5. Integration: retrospective references run history
# ---------------------------------------------------------------------------
@test "run-history: retrospective agent references run-history.db" {
  grep -q "run-history" "$RETROSPECTIVE" \
    || fail "fg-700-retrospective.md does not reference run history store"
}

# ---------------------------------------------------------------------------
# 6. Integration: state-schema documents run-history.db
# ---------------------------------------------------------------------------
@test "run-history: state-schema.md lists run-history.db" {
  grep -q "run-history.db" "$STATE_SCHEMA" \
    || fail "state-schema.md does not document run-history.db"
}

# ---------------------------------------------------------------------------
# 7. Integration: preflight-constraints includes run_history config
# ---------------------------------------------------------------------------
@test "run-history: preflight-constraints.md includes run_history validation" {
  grep -q "run_history" "$PREFLIGHT" \
    || fail "preflight-constraints.md does not include run_history config validation"
}

# ---------------------------------------------------------------------------
# 8. FTS5 tokenizer configured
# ---------------------------------------------------------------------------
@test "run-history: FTS5 uses unicode61 tokenizer" {
  grep -q "unicode61" "$SCHEMA_FILE" \
    || fail "FTS5 tokenizer not set to unicode61"
}

# ---------------------------------------------------------------------------
# 9. Schema uses CASCADE deletes
# ---------------------------------------------------------------------------
@test "run-history: findings table has ON DELETE CASCADE" {
  grep -A5 "CREATE TABLE.*findings" "$SCHEMA_FILE" | grep -q "ON DELETE CASCADE" \
    || fail "findings FK missing ON DELETE CASCADE"
}
```

- [ ] **Step 2: Verify the tests pass**

```bash
./tests/lib/bats-core/bin/bats tests/contract/run-history-schema.bats
```

Expected: All tests PASS (after Tasks 1-5 are complete).

- [ ] **Step 3: Commit**

```bash
git add tests/contract/run-history-schema.bats
git commit -m "test(run-history): add contract tests for schema and integration"
```

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add run-history.db to `.forge/` survival list**

In the Gotchas > Structural section, find the line listing files that survive `/forge-reset` and add `run-history.db`:

```
- `explore-cache.json`, `plan-cache/`, `code-graph.db`, `trust.json`, `events.jsonl`, `playbook-analytics.json`, and `run-history.db` survive `/forge-reset`.
```

- [ ] **Step 2: Add to v2.0 features table**

Add a new row to the features table:

```
| Run history store (F29) | `run_history.*` | SQLite FTS5 at `.forge/run-history.db`. Written by retrospective, queried by insights/ask/MCP |
```

- [ ] **Step 3: Add config keys to supporting systems section**

In the "Supporting systems" paragraph, mention `run_history.enabled`, `run_history.retention_days`.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude-md): add run history store feature documentation"
```
