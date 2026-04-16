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
  # Skip FTS5 block if module not compiled in (common on macOS CI)
  if ! sqlite3 :memory: "CREATE VIRTUAL TABLE t USING fts5(c)" 2>/dev/null; then
    sed '/CREATE VIRTUAL TABLE.*fts5/,/);/d' "$SCHEMA_FILE" | sqlite3 :memory:
  else
    sqlite3 :memory: < "$SCHEMA_FILE"
  fi
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
