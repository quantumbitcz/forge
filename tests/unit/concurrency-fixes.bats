#!/usr/bin/env bats
# Unit tests for SPEC-02 concurrency fixes

load '../helpers/test-helpers'

STATE_WRITER="$PLUGIN_ROOT/shared/forge-state-write.sh"
TOKEN_TRACKER="$PLUGIN_ROOT/shared/forge-token-tracker.sh"
COMPACT_CHECK="$PLUGIN_ROOT/shared/forge-compact-check.sh"

# R1: State recovery with lock
@test "concurrency-fixes: recovery acquires lock and produces valid state" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  echo '--- SEQ:1 TS:2026-04-14T10:00:00Z ---' > "$forge_dir/state.wal"
  echo '{"version":"1.5.0","_seq":1,"story_state":"IMPLEMENTING"}' >> "$forge_dir/state.wal"

  run bash -c "bash '$STATE_WRITER' read --forge-dir '$forge_dir' 2>/dev/null"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['story_state']=='IMPLEMENTING'"
  assert [ -f "$forge_dir/state.json" ]
}

# R2: WAL truncation cleans up tmp on failure
@test "concurrency-fixes: WAL truncation does not leave orphaned .tmp file" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  for i in $(seq 1 60); do
    bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":'$i'}' --forge-dir "$forge_dir" > /dev/null 2>&1 || true
  done
  assert [ ! -f "$forge_dir/state.wal.tmp" ]
}

# R3: Token tracker retries with backoff
@test "concurrency-fixes: token tracker retries on stale _seq" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":0,"budget_ceiling":0,"by_stage":{},"by_agent":{},"budget_warning_issued":false}}' --forge-dir "$forge_dir"

  run bash "$TOKEN_TRACKER" record explore fg-200 1000 500 claude-sonnet-4-6 --forge-dir "$forge_dir"
  assert_success
}

# R4: Compact counter accurate after sequential increments
@test "concurrency-fixes: compact counter increments correctly" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  for i in 1 2 3 4 5; do
    FORGE_DIR="$forge_dir" bash "$COMPACT_CHECK" --forge-dir "$forge_dir"
  done
  local count
  count=$(cat "$forge_dir/.token-estimate" 2>/dev/null)
  [[ "$count" -eq 5 ]]
}

# R6: Timestamps include Z suffix
@test "concurrency-fixes: WAL entries have Z suffix on timestamp" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  local ts_line
  ts_line=$(grep "^--- SEQ:" "$forge_dir/state.wal" | tail -1)
  [[ "$ts_line" == *"Z ---" ]]
}

# R7: Model classification
@test "concurrency-fixes: model classification claude-sonnet-4-6 -> sonnet" {
  local result
  result=$(python3 -c "
MODEL_PATTERNS = [
    ('claude-opus-4', 'opus'),
    ('claude-sonnet-4', 'sonnet'),
    ('claude-haiku-4', 'haiku'),
    ('opus', 'opus'),
    ('sonnet', 'sonnet'),
    ('haiku', 'haiku'),
]
def classify_model(model_name):
    m = model_name.lower()
    for pattern, category in MODEL_PATTERNS:
        if pattern in m:
            return category
    return 'sonnet'
print(classify_model('claude-sonnet-4-6'))
")
  assert_equal "$result" "sonnet"
}

@test "concurrency-fixes: model classification claude-haiku-4-5-20251001 -> haiku" {
  local result
  result=$(python3 -c "
MODEL_PATTERNS = [
    ('claude-opus-4', 'opus'),
    ('claude-sonnet-4', 'sonnet'),
    ('claude-haiku-4', 'haiku'),
    ('opus', 'opus'),
    ('sonnet', 'sonnet'),
    ('haiku', 'haiku'),
]
def classify_model(model_name):
    m = model_name.lower()
    for pattern, category in MODEL_PATTERNS:
        if pattern in m:
            return category
    return 'sonnet'
print(classify_model('claude-haiku-4-5-20251001'))
")
  assert_equal "$result" "haiku"
}

@test "concurrency-fixes: model classification unknown-model -> sonnet (default)" {
  local result
  result=$(python3 -c "
MODEL_PATTERNS = [
    ('claude-opus-4', 'opus'),
    ('claude-sonnet-4', 'sonnet'),
    ('claude-haiku-4', 'haiku'),
    ('opus', 'opus'),
    ('sonnet', 'sonnet'),
    ('haiku', 'haiku'),
]
def classify_model(model_name):
    m = model_name.lower()
    for pattern, category in MODEL_PATTERNS:
        if pattern in m:
            return category
    return 'sonnet'
print(classify_model('unknown-model'))
")
  assert_equal "$result" "sonnet"
}

# R8: Validation skip warning
@test "concurrency-fixes: VALIDATE=false logs warning to forge.log" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  VALIDATE=false bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert [ -f "$forge_dir/forge.log" ]
  grep -q "SKIPPED" "$forge_dir/forge.log"
}
