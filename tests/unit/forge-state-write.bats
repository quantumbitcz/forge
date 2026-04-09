#!/usr/bin/env bats
# Unit tests: forge-state-write.sh — atomic JSON writes with WAL and versioning.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state-write.sh"

# ---------------------------------------------------------------------------
# 1. Script existence and structure
# ---------------------------------------------------------------------------

@test "forge-state-write: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-state-write: has bash shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ---------------------------------------------------------------------------
# 2. Write operation
# ---------------------------------------------------------------------------

@test "forge-state-write: write creates state.json from JSON input" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","story_state":"PREFLIGHT"}' --forge-dir "$forge_dir"
  assert_success

  assert [ -f "$forge_dir/state.json" ]
  local state
  state=$(cat "$forge_dir/state.json")
  echo "$state" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['story_state']=='PREFLIGHT'"
}

@test "forge-state-write: write increments _seq counter" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success
  local seq1
  seq1=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['_seq'])")
  assert_equal "$seq1" "1"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":1}' --forge-dir "$forge_dir"
  assert_success
  local seq2
  seq2=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['_seq'])")
  assert_equal "$seq2" "2"
}

@test "forge-state-write: write appends to WAL" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success
  assert [ -f "$forge_dir/state.wal" ]

  local wal_entries
  wal_entries=$(grep -c "^--- SEQ:" "$forge_dir/state.wal")
  assert_equal "$wal_entries" "1"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":1}' --forge-dir "$forge_dir"
  assert_success
  wal_entries=$(grep -c "^--- SEQ:" "$forge_dir/state.wal")
  assert_equal "$wal_entries" "2"
}

@test "forge-state-write: rejects stale writes (lower _seq)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success

  # Try to write with _seq=0 again (stale — current file has _seq=1)
  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_failure
  assert_output --partial "stale"
}

# ---------------------------------------------------------------------------
# 3. Read operation
# ---------------------------------------------------------------------------

@test "forge-state-write: read returns valid JSON" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0,"story_state":"EXPLORING"}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" read --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['story_state']=='EXPLORING'"
}

@test "forge-state-write: read fails when neither state.json nor WAL exists" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" read --forge-dir "$forge_dir"
  assert_failure
}

# ---------------------------------------------------------------------------
# 4. Recovery
# ---------------------------------------------------------------------------

@test "forge-state-write: recover restores from WAL when state.json missing" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0,"story_state":"IMPLEMENTING"}' --forge-dir "$forge_dir"
  assert [ -f "$forge_dir/state.wal" ]

  # Delete state.json, simulating corruption
  rm "$forge_dir/state.json"

  run bash "$SCRIPT" recover --forge-dir "$forge_dir"
  assert_success
  assert [ -f "$forge_dir/state.json" ]

  local restored_state
  restored_state=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['story_state'])")
  assert_equal "$restored_state" "IMPLEMENTING"
}

# ---------------------------------------------------------------------------
# 5. WAL truncation
# ---------------------------------------------------------------------------

@test "forge-state-write: WAL truncates at 50 entries" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  for i in $(seq 0 54); do
    bash "$SCRIPT" write "{\"version\":\"1.5.0\",\"_seq\":$i}" --forge-dir "$forge_dir"
  done

  local wal_entries
  wal_entries=$(grep -c "^--- SEQ:" "$forge_dir/state.wal")
  assert [ "$wal_entries" -le 50 ]
}

# ---------------------------------------------------------------------------
# 6. No leftover temp files
# ---------------------------------------------------------------------------

@test "forge-state-write: no .tmp file left after successful write" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success
  assert [ ! -f "$forge_dir/state.json.tmp" ]
}

# ---------------------------------------------------------------------------
# 7. Concurrent write safety (flock)
# ---------------------------------------------------------------------------

@test "forge-state-write: concurrent writes do not corrupt state" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"

  # Launch 5 concurrent writes
  for i in $(seq 1 5); do
    bash "$SCRIPT" write "{\"version\":\"1.5.0\",\"_seq\":$i,\"writer\":$i}" --forge-dir "$forge_dir" &
  done
  wait

  # state.json must be valid JSON with _seq >= 1
  run python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert d['_seq'] >= 1, f'_seq={d[\"_seq\"]}'
assert 'version' in d
print('OK')
"
  assert_success
  assert_output "OK"

  # Verify WAL has multiple entries (proving serialized writes happened)
  local wal_count
  wal_count=$(grep -c "^--- SEQ:" "$forge_dir/state.wal")
  assert [ "$wal_count" -ge 2 ]
}

# ---------------------------------------------------------------------------
# 8. Argument guard
# ---------------------------------------------------------------------------

@test "forge-state-write: write rejects --forge-dir before JSON" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  run bash "$SCRIPT" write --forge-dir "$forge_dir" '{"version":"1.5.0"}'
  assert_failure
  assert_output --partial "requires JSON content"
}

# ---------------------------------------------------------------------------
# 9. Recovery edge cases
# ---------------------------------------------------------------------------

@test "forge-state-write: recover fails with empty WAL" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  touch "$forge_dir/state.wal"
  run bash "$SCRIPT" recover --forge-dir "$forge_dir"
  assert_failure
}
