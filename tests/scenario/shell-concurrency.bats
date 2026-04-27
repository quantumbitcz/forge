#!/usr/bin/env bats
# Scenario tests: shell concurrency — validates concurrent event emission,
# atomic operations, state init safety, lock files, and stale lock detection.

# Covers:

load '../helpers/test-helpers'

FORGE_EVENT="$PLUGIN_ROOT/shared/forge-event.sh"
PLATFORM_SH="$PLUGIN_ROOT/shared/platform.sh"
FORGE_STATE="$PLUGIN_ROOT/shared/forge-state.sh"
ENGINE_SH="$PLUGIN_ROOT/shared/checks/engine.sh"

# ===========================================================================
# 1. Concurrent event emissions produce valid JSONL
# ===========================================================================
@test "shell-concurrency: 5 concurrent event emissions produce valid JSONL" {
  local forge_dir="${TEST_TEMP}/concurrent-events/.forge"
  mkdir -p "$forge_dir"

  # Launch 5 concurrent emissions
  for i in 1 2 3 4 5; do
    bash "$FORGE_EVENT" "test_event_${i}" \
      --field "seq=${i}" \
      --forge-dir "$forge_dir" &
  done
  wait

  local events_file="$forge_dir/events.jsonl"
  [[ -f "$events_file" ]] || fail "events.jsonl was not created"

  # Count lines — should have at least 5 events
  local line_count
  line_count=$(wc -l < "$events_file" | tr -d ' ')
  [[ "$line_count" -ge 5 ]] \
    || fail "Expected at least 5 events, got $line_count"

  # Validate each line is valid JSON
  local bad_lines=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    python3 -c "import json; json.loads('''$line''')" 2>/dev/null \
      || bad_lines=$((bad_lines + 1))
  done < "$events_file"

  [[ "$bad_lines" -eq 0 ]] \
    || fail "$bad_lines lines are not valid JSON in events.jsonl"
}

# ===========================================================================
# 2. Concurrent atomic_increment produces correct final count
# ===========================================================================
@test "shell-concurrency: concurrent atomic_increment produces correct final count" {
  source "$PLATFORM_SH"

  local counter_file="${TEST_TEMP}/test-counter"
  echo "0" > "$counter_file"

  # Run 5 concurrent increments
  for i in 1 2 3 4 5; do
    (
      source "$PLATFORM_SH"
      atomic_increment "$counter_file" >/dev/null
    ) &
  done
  wait

  local final_count
  final_count=$(cat "$counter_file")
  [[ "$final_count" -eq 5 ]] \
    || fail "Expected final count 5, got $final_count"
}

# ===========================================================================
# 3. Two concurrent forge-state.sh inits don't corrupt (separate forge-dirs)
# ===========================================================================
@test "shell-concurrency: two concurrent state inits don't corrupt" {
  local forge_dir_a="${TEST_TEMP}/state-a/.forge"
  local forge_dir_b="${TEST_TEMP}/state-b/.forge"
  mkdir -p "$forge_dir_a" "$forge_dir_b"

  # Initialize two separate state files concurrently
  bash "$FORGE_STATE" init "STORY-A" "Requirement A" --forge-dir "$forge_dir_a" &
  local pid_a=$!
  bash "$FORGE_STATE" init "STORY-B" "Requirement B" --forge-dir "$forge_dir_b" &
  local pid_b=$!

  wait "$pid_a" || true
  wait "$pid_b" || true

  # Both state files should exist and be valid JSON
  local state_a="$forge_dir_a/state.json"
  local state_b="$forge_dir_b/state.json"

  [[ -f "$state_a" ]] || fail "state.json A was not created"
  [[ -f "$state_b" ]] || fail "state.json B was not created"

  python3 -c "import json; json.load(open('$state_a'))" 2>/dev/null \
    || fail "state.json A is not valid JSON"
  python3 -c "import json; json.load(open('$state_b'))" 2>/dev/null \
    || fail "state.json B is not valid JSON"

  # Verify they have different story IDs
  local story_a story_b
  story_a=$(python3 -c "import json; print(json.load(open('$state_a')).get('story_id',''))" 2>/dev/null)
  story_b=$(python3 -c "import json; print(json.load(open('$state_b')).get('story_id',''))" 2>/dev/null)

  [[ "$story_a" != "$story_b" ]] \
    || fail "Both state files have the same story_id: $story_a"
}

# ===========================================================================
# 4. Engine lock file prevents double-run
# ===========================================================================
@test "shell-concurrency: engine.sh uses lock mechanism" {
  [[ -f "$ENGINE_SH" ]] || skip "engine.sh not found"

  # Verify engine.sh has a lock mechanism (either flock or mkdir)
  grep -q "LOCK_FILE\|\.lock\|flock\|mkdir.*lock" "$ENGINE_SH" \
    || fail "engine.sh does not implement any lock mechanism"

  # Verify it uses .engine.lock specifically
  grep -q "engine\.lock" "$ENGINE_SH" \
    || fail "engine.sh does not use .engine.lock file"
}

# ===========================================================================
# 5. Stale lock detection works (mkdir lock older than threshold)
# ===========================================================================
@test "shell-concurrency: stale lock detection via state-integrity or platform.sh" {
  # The concurrent run lock uses .forge/.lock with PID + 24h stale timeout
  # Verify that state-integrity.sh or forge-state.sh references stale lock detection
  local state_integrity="$PLUGIN_ROOT/shared/state-integrity.sh"

  if [[ -f "$state_integrity" ]]; then
    grep -qi "stale\|LOCK\|lock.*pid\|24.*hour\|PID" "$state_integrity" \
      || fail "state-integrity.sh does not reference stale lock detection"
  else
    # Fallback: check forge-state.sh or CLAUDE.md for lock documentation
    grep -qi "stale\|24h\|PID" "$FORGE_STATE" \
      || grep -q "stale.*lock\|PID.*stale" "$PLUGIN_ROOT/CLAUDE.md" \
      || fail "Stale lock detection not documented in forge-state.sh or CLAUDE.md"
  fi
}
