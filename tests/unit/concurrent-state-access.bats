#!/usr/bin/env bats
# Unit tests: concurrent state.json access — validates parallel reads/writes,
# lock file behavior, WAL crash recovery, _seq versioning under contention,
# stale lock detection, and lock cleanup.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state-write.sh"

# ---------------------------------------------------------------------------
# 1. Two concurrent forge-state-write.sh calls don't corrupt JSON
# ---------------------------------------------------------------------------

@test "concurrent-state: two parallel writes produce valid JSON" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"

  # Launch 2 concurrent writes
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":1,"writer":"A"}' --forge-dir "$forge_dir" &
  local pid_a=$!
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":1,"writer":"B"}' --forge-dir "$forge_dir" &
  local pid_b=$!

  # At least one should succeed (the other may get stale-write rejection)
  wait "$pid_a" || true
  wait "$pid_b" || true

  # state.json must be valid JSON regardless of which write won
  run python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert 'version' in d, 'Missing version key'
assert d['_seq'] >= 1, f'_seq should be >= 1, got {d[\"_seq\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "concurrent-state: 10 sequential writes all produce valid JSON" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  for i in $(seq 0 9); do
    run bash "$SCRIPT" write "{\"version\":\"1.5.0\",\"_seq\":$i,\"writer\":$i}" --forge-dir "$forge_dir"
    assert_success
  done

  # Final state.json must be valid with _seq=10
  run python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert d['_seq'] == 10, f'Expected _seq=10, got {d[\"_seq\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "concurrent-state: 5 concurrent writes all produce valid final state" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"

  # Launch 5 concurrent writes (some will fail with stale-write, that is OK)
  for i in $(seq 1 5); do
    bash "$SCRIPT" write "{\"version\":\"1.5.0\",\"_seq\":$i,\"writer\":$i}" --forge-dir "$forge_dir" &
  done
  wait

  # state.json must be valid JSON
  run python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert d['_seq'] >= 1, f'_seq should be >= 1, got {d[\"_seq\"]}'
assert 'version' in d
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 2. Lock file prevents race conditions
# ---------------------------------------------------------------------------

@test "concurrent-state: write uses lock mechanism (flock or mkdir)" {
  # Verify the script uses a locking mechanism
  grep -q "flock\|lockdir\|\.lock" "$SCRIPT" \
    || fail "forge-state-write.sh does not implement any lock mechanism"
}

@test "concurrent-state: mkdir-based lock used as fallback when flock unavailable" {
  # Verify the script has a mkdir-based fallback for macOS/systems without flock
  grep -q "mkdir.*lock" "$SCRIPT" \
    || fail "forge-state-write.sh does not implement mkdir-based lock fallback"
}

@test "concurrent-state: lock acquisition has timeout to prevent deadlock" {
  # Verify the script has a retry limit on lock acquisition
  grep -q "lock_attempts\|retries\|_lock_attempts" "$SCRIPT" \
    || fail "forge-state-write.sh does not have lock acquisition timeout"
}

@test "concurrent-state: lock file path is inside forge directory" {
  # The lock should be scoped to the .forge directory, not system-wide
  grep -q 'FORGE_DIR.*lock\|forge_dir.*lock\|lock_file.*FORGE_DIR' "$SCRIPT" \
    || grep -q 'state-write\.lock' "$SCRIPT" \
    || fail "Lock file should be inside the forge directory"
}

# ---------------------------------------------------------------------------
# 3. WAL (write-ahead log) recovery after crash
# ---------------------------------------------------------------------------

@test "concurrent-state: WAL file created on write" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success
  assert [ -f "$forge_dir/state.wal" ]
}

@test "concurrent-state: recover restores latest state from WAL" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  # Write 3 sequential states
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0,"stage":"PREFLIGHT"}' --forge-dir "$forge_dir"
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":1,"stage":"EXPLORING"}' --forge-dir "$forge_dir"
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":2,"stage":"IMPLEMENTING"}' --forge-dir "$forge_dir"

  # Simulate crash by deleting state.json
  rm "$forge_dir/state.json"

  run bash "$SCRIPT" recover --forge-dir "$forge_dir"
  assert_success

  # Verify recovered state is the latest
  run python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert d['stage'] == 'IMPLEMENTING', f'Expected IMPLEMENTING, got {d[\"stage\"]}'
assert d['_seq'] == 3, f'Expected _seq=3, got {d[\"_seq\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "concurrent-state: recover fails gracefully when WAL is missing" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" recover --forge-dir "$forge_dir"
  assert_failure
}

@test "concurrent-state: recover fails gracefully when WAL has no valid entries" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  # Create WAL with no valid JSON entries
  {
    echo "--- SEQ:1 TS:2026-01-01T00:00:00Z ---"
    echo "this is not json"
  } > "$forge_dir/state.wal"

  run bash "$SCRIPT" recover --forge-dir "$forge_dir"
  assert_failure
}

@test "concurrent-state: read auto-recovers from WAL when state.json missing" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0,"mode":"bugfix"}' --forge-dir "$forge_dir"
  rm "$forge_dir/state.json"

  # Read should trigger auto-recovery from WAL
  run bash "$SCRIPT" read --forge-dir "$forge_dir"
  assert_success

  # The output includes a WARNING line on stderr and JSON on stdout
  # Extract just the JSON portion and validate
  run python3 -c "
import json, sys
# The read command outputs JSON to stdout; bats captures both stdout and stderr
# Filter to find the JSON object
lines = '''$output'''.strip().split('\n')
json_lines = [l for l in lines if l.strip().startswith('{') or l.strip().startswith('\"') or l.strip().startswith('}') or l.strip().startswith(' ')]
json_str = '\n'.join(json_lines)
d = json.loads(json_str)
assert d['mode'] == 'bugfix', f'Expected bugfix mode, got {d[\"mode\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 4. _seq versioning increments correctly under concurrent access
# ---------------------------------------------------------------------------

@test "concurrent-state: _seq increments by 1 on each write" {
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

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":2}' --forge-dir "$forge_dir"
  assert_success
  local seq3
  seq3=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['_seq'])")
  assert_equal "$seq3" "3"
}

@test "concurrent-state: stale _seq rejected" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  # First write: _seq 0 -> file has _seq 1
  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success

  # Try stale write with _seq=0 (current file is _seq=1)
  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_failure
  assert_output --partial "stale"
}

@test "concurrent-state: _seq monotonically increases across concurrent writes" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"

  # Run 5 concurrent writes — some will succeed, some will fail with stale
  for i in $(seq 1 5); do
    bash "$SCRIPT" write "{\"version\":\"1.5.0\",\"_seq\":$i}" --forge-dir "$forge_dir" &
  done
  wait

  # Final _seq should be >= 2 (at least initial + 1 successful concurrent write)
  local final_seq
  final_seq=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['_seq'])")
  [[ "$final_seq" -ge 2 ]] \
    || fail "Expected _seq >= 2 after concurrent writes, got $final_seq"
}

@test "concurrent-state: WAL entries match _seq sequence" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":1}' --forge-dir "$forge_dir"
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":2}' --forge-dir "$forge_dir"

  # WAL should have 3 entries with sequential SEQ numbers
  local wal_entries
  wal_entries=$(grep -c "^--- SEQ:" "$forge_dir/state.wal")
  [[ "$wal_entries" -eq 3 ]] || fail "Expected 3 WAL entries, got $wal_entries"

  # Verify SEQ numbers are 1, 2, 3
  run python3 -c "
import re
with open('$forge_dir/state.wal') as f:
    content = f.read()
seqs = [int(m) for m in re.findall(r'SEQ:(\d+)', content)]
assert seqs == [1, 2, 3], f'Expected SEQ [1,2,3], got {seqs}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 5. Stale lock detection (24h timeout)
# ---------------------------------------------------------------------------

@test "concurrent-state: stale lock concept documented in CLAUDE.md" {
  grep -qi "stale\|24h" "$PLUGIN_ROOT/CLAUDE.md" \
    || fail "Stale lock detection not documented in CLAUDE.md"
  grep -q "PID" "$PLUGIN_ROOT/CLAUDE.md" \
    || fail "PID-based lock not documented in CLAUDE.md"
}

@test "concurrent-state: lock acquisition retries before giving up" {
  # The script should retry lock acquisition rather than immediately failing
  # Verify retry/polling logic exists
  grep -q "sleep\|retries\|attempts\|_lock_attempts" "$SCRIPT" \
    || fail "No retry logic found in lock acquisition"
}

@test "concurrent-state: mkdir lock contention resolves within 10 seconds" {
  # On systems without flock (macOS), the script uses mkdir-based locking
  # and retries up to 50 times with 0.1s sleep = 5s max wait.
  # On systems WITH flock (Linux), flock is used instead and the mkdir lockdir
  # does not block writes. This test only validates the mkdir path.
  if command -v flock &>/dev/null; then
    skip "flock available — mkdir lock path not exercised on this platform"
  fi

  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  # Create a lockdir to simulate contention
  local lock_dir="$forge_dir/.state-write.lockdir"
  mkdir -p "$lock_dir"

  # Write should eventually fail (lock timeout) rather than hanging
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir" &
  local pid=$!
  # Wait up to 10 seconds
  local waited=0
  while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 100 ]]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null || true
    fail "Write should have timed out within 10s, but it hung"
  fi
  # Collect exit code without triggering bats errexit
  local exit_code=0
  wait "$pid" 2>/dev/null || exit_code=$?
  [[ $exit_code -ne 0 ]] \
    || fail "Write should fail when lock cannot be acquired, but it succeeded"

  # Clean up lock
  rmdir "$lock_dir" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 6. Lock file cleanup after successful write
# ---------------------------------------------------------------------------

@test "concurrent-state: no leftover lock directory after successful write" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success

  # Neither lock dir nor lock file should remain
  [[ ! -d "$forge_dir/.state-write.lockdir" ]] \
    || fail "Lock directory should be cleaned up after successful write"
}

@test "concurrent-state: no leftover tmp file after successful write" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success

  [[ ! -f "$forge_dir/state.json.tmp" ]] \
    || fail "Temp file should be cleaned up after successful write"
}

@test "concurrent-state: lock released after failed write (stale rejection)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  # First write succeeds
  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"

  # Second write with stale _seq fails
  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_failure

  # Lock should still be released even on failure
  [[ ! -d "$forge_dir/.state-write.lockdir" ]] \
    || fail "Lock directory should be cleaned up even after failed write"
}

@test "concurrent-state: subsequent write succeeds after previous write completes" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  # Chain 3 writes — each must succeed and release the lock for the next
  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0,"step":"first"}' --forge-dir "$forge_dir"
  assert_success

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":1,"step":"second"}' --forge-dir "$forge_dir"
  assert_success

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":2,"step":"third"}' --forge-dir "$forge_dir"
  assert_success

  # Final state should reflect the third write
  run python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert d['step'] == 'third', f'Expected third, got {d[\"step\"]}'
assert d['_seq'] == 3, f'Expected _seq=3, got {d[\"_seq\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "concurrent-state: WAL truncation does not leave stale lock" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  # Write enough entries to trigger WAL truncation (>50)
  for i in $(seq 0 54); do
    bash "$SCRIPT" write "{\"version\":\"1.5.0\",\"_seq\":$i}" --forge-dir "$forge_dir"
  done

  # Verify no leftover lock artifacts
  [[ ! -d "$forge_dir/.state-write.lockdir" ]] \
    || fail "Lock directory should not remain after WAL truncation"

  # Verify WAL was truncated
  local wal_entries
  wal_entries=$(grep -c "^--- SEQ:" "$forge_dir/state.wal")
  [[ "$wal_entries" -le 50 ]] \
    || fail "WAL should have at most 50 entries after truncation, got $wal_entries"
}
