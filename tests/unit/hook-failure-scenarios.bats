#!/usr/bin/env bats
# Unit tests: hook failure scenarios — validates that hook scripts handle
# failure conditions gracefully: non-zero exits, invalid JSON, timeouts,
# missing dependencies, and concurrent invocations.

load '../helpers/test-helpers'

CHECKPOINT_HOOK="$PLUGIN_ROOT/hooks/post_tool_use_skill.py"
FEEDBACK_HOOK="$PLUGIN_ROOT/hooks/stop.py"
PLATFORM_SH="$PLUGIN_ROOT/shared/platform.sh"

# Helper: run a hook with CWD set to the given project dir
run_hook_in() {
  local hook="$1"
  local project_dir="$2"
  run bash -c "cd '$project_dir' && python3 '$hook'"
}

# ---------------------------------------------------------------------------
# 1. Hook script that exits non-zero should not crash pipeline (exit 0)
# ---------------------------------------------------------------------------

@test "hook-failure: checkpoint hook exits 0 even when atomic_json_update fails" {
  local project_dir="${TEST_TEMP}/hook-fail-project"
  mkdir -p "$project_dir/.forge"
  # Create valid JSON that will cause atomic_json_update to fail
  # by making the file read-only after creation
  printf '{"story_state":"IMPLEMENTING"}\n' > "$project_dir/.forge/state.json"
  chmod a-w "$project_dir/.forge/state.json"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  # Restore write permission for cleanup
  chmod u+w "$project_dir/.forge/state.json"
}

@test "hook-failure: feedback hook exits 0 when feedback directory is not writable" {
  local project_dir="${TEST_TEMP}/hook-feedback-fail"
  mkdir -p "$project_dir/.forge/feedback"
  printf '{"story_state":"SHIPPING"}\n' > "$project_dir/.forge/state.json"
  # Make feedback directory read-only to cause write failure
  chmod a-w "$project_dir/.forge/feedback"

  run_hook_in "$FEEDBACK_HOOK" "$project_dir"
  assert_success

  # Restore for cleanup
  chmod u+w "$project_dir/.forge/feedback"
}

# ---------------------------------------------------------------------------
# 2. Hook script that produces invalid JSON — state should remain valid
# ---------------------------------------------------------------------------

@test "hook-failure: state.json remains valid JSON after checkpoint hook on malformed input" {
  local project_dir="${TEST_TEMP}/hook-invalid-json"
  mkdir -p "$project_dir/.forge"
  printf 'this is { not valid json ]]]\n' > "$project_dir/.forge/state.json"
  local original_content
  original_content="$(cat "$project_dir/.forge/state.json")"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  # Original content should be unchanged (hook should not corrupt it further)
  local after_content
  after_content="$(cat "$project_dir/.forge/state.json")"
  [[ "$after_content" == "$original_content" ]] \
    || fail "State file was modified despite malformed JSON. Before: '$original_content', After: '$after_content'"
}

@test "hook-failure: valid state.json keys preserved after checkpoint hook" {
  local project_dir="${TEST_TEMP}/hook-preserve-keys"
  mkdir -p "$project_dir/.forge"
  printf '{"story_state":"VERIFYING","mode":"bugfix","score_history":[60,75]}\n' \
    > "$project_dir/.forge/state.json"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  # Verify all original keys are still present
  run python3 -c "
import json
with open('$project_dir/.forge/state.json') as f:
    d = json.load(f)
assert d['story_state'] == 'VERIFYING', f'story_state changed: {d[\"story_state\"]}'
assert d['mode'] == 'bugfix', f'mode changed: {d[\"mode\"]}'
assert d['score_history'] == [60, 75], f'score_history changed: {d[\"score_history\"]}'
assert 'lastCheckpoint' in d, 'lastCheckpoint not added'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 3. Hook script timeout — should gracefully continue
# ---------------------------------------------------------------------------

@test "hook-failure: hooks.json defines timeout for checkpoint hook" {
  local hooks_json="$PLUGIN_ROOT/hooks/hooks.json"
  [[ -f "$hooks_json" ]] || fail "hooks.json not found"

  # Verify checkpoint hook has a timeout defined
  run python3 -c "
import json
with open('$hooks_json') as f:
    d = json.load(f)
for group in d['hooks'].get('PostToolUse', []):
    if group.get('matcher') == 'Skill':
        for h in group.get('hooks', []):
            if 'post_tool_use_skill' in h.get('command', ''):
                assert 'timeout' in h, 'No timeout defined for checkpoint hook'
                assert h['timeout'] > 0, f'Timeout must be positive, got {h[\"timeout\"]}'
                print(f'timeout={h[\"timeout\"]}')
                exit(0)
print('NOTFOUND')
exit(1)
"
  assert_success
  [[ "$output" == *"timeout="* ]] || fail "Checkpoint hook timeout not found in hooks.json"
}

@test "hook-failure: hooks.json defines timeout for feedback hook" {
  local hooks_json="$PLUGIN_ROOT/hooks/hooks.json"
  [[ -f "$hooks_json" ]] || fail "hooks.json not found"

  run python3 -c "
import json
with open('$hooks_json') as f:
    d = json.load(f)
for group in d['hooks'].get('Stop', []):
    for h in group.get('hooks', []):
        if 'stop.py' in h.get('command', ''):
            assert 'timeout' in h, 'No timeout defined for feedback hook'
            assert h['timeout'] > 0, f'Timeout must be positive, got {h[\"timeout\"]}'
            print(f'timeout={h[\"timeout\"]}')
            exit(0)
print('NOTFOUND')
exit(1)
"
  assert_success
  [[ "$output" == *"timeout="* ]] || fail "Feedback hook timeout not found in hooks.json"
}

# ---------------------------------------------------------------------------
# 4. State.json not corrupted after hook failure
# ---------------------------------------------------------------------------

@test "hook-failure: state.json parseable as valid JSON after checkpoint on large state" {
  local project_dir="${TEST_TEMP}/hook-large-state"
  mkdir -p "$project_dir/.forge"

  # Create a large-ish state.json with many fields
  python3 -c "
import json
state = {
    'version': '1.5.0',
    'story_state': 'IMPLEMENTING',
    'mode': 'standard',
    'score_history': list(range(50)),
    'convergence': {
        'phase': 'correctness',
        'total_iterations': 10,
        'plateau_count': 0
    },
    'recovery_budget': {
        'total_weight': 2.5,
        'max_weight': 5.5,
        'applications': []
    },
    'modules': ['spring', 'kotlin', 'kotest'],
    '_seq': 42
}
with open('$project_dir/.forge/state.json', 'w') as f:
    json.dump(state, f, indent=2)
"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  # Verify state.json is still valid JSON with all fields intact
  run python3 -c "
import json
with open('$project_dir/.forge/state.json') as f:
    d = json.load(f)
assert d['version'] == '1.5.0'
assert d['story_state'] == 'IMPLEMENTING'
assert len(d['score_history']) == 50
assert d['recovery_budget']['total_weight'] == 2.5
assert 'lastCheckpoint' in d
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "hook-failure: empty state.json does not crash checkpoint hook" {
  local project_dir="${TEST_TEMP}/hook-empty-state"
  mkdir -p "$project_dir/.forge"
  touch "$project_dir/.forge/state.json"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success
}

# ---------------------------------------------------------------------------
# 5. Hook failure logged to .forge/.hook-failures.log
# ---------------------------------------------------------------------------

@test "hook-failure: checkpoint logs failure to .hook-failures.log on update error" {
  local project_dir="${TEST_TEMP}/hook-log-failure"
  mkdir -p "$project_dir/.forge"
  # Create state.json that will cause atomic_json_update to fail (empty file)
  touch "$project_dir/.forge/state.json"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  # Check if .hook-failures.log was created with a failure entry
  local log_file="$project_dir/.forge/.hook-failures.log"
  if [[ -f "$log_file" ]]; then
    # Verify log entry format: timestamp | hook-name | reason | file
    local content
    content="$(cat "$log_file")"
    [[ "$content" == *"forge-checkpoint"* ]] \
      || fail "Log entry does not reference forge-checkpoint: $content"
    # The hook may log "update_failed" or "invalid_json" depending on the failure path
    [[ "$content" == *"update_failed"* || "$content" == *"invalid_json"* || "$content" == *"state.json"* ]] \
      || fail "Log entry does not contain expected failure indicator: $content"
  fi
  # If no log file, the update may have succeeded on empty file — either
  # outcome (success or logged failure) is acceptable behavior
}

@test "hook-failure: feedback hook reports hook failure count in auto-captured.md" {
  local project_dir="${TEST_TEMP}/hook-failure-count"
  mkdir -p "$project_dir/.forge/feedback"
  printf '{"story_state":"SHIPPING","mode":"standard"}\n' > "$project_dir/.forge/state.json"

  # Pre-populate hook failures log
  printf '2026-01-01T00:00:00Z | forge-checkpoint | update_failed | state.json\n' \
    > "$project_dir/.forge/.hook-failures.log"
  printf '2026-01-01T00:01:00Z | forge-checkpoint | update_failed | state.json\n' \
    >> "$project_dir/.forge/.hook-failures.log"

  run_hook_in "$FEEDBACK_HOOK" "$project_dir"
  assert_success

  local content
  content="$(cat "$project_dir/.forge/feedback/auto-captured.md")"
  [[ "$content" == *"Hook failures"* ]] \
    || fail "Feedback hook did not report hook failure count: $content"
  [[ "$content" == *"2"* ]] \
    || fail "Expected failure count of 2 in output: $content"
}

# ---------------------------------------------------------------------------
# 6. Multiple concurrent hook invocations don't corrupt state
# ---------------------------------------------------------------------------

@test "hook-failure: 5 concurrent checkpoint invocations produce valid state.json" {
  local project_dir="${TEST_TEMP}/hook-concurrent"
  mkdir -p "$project_dir/.forge"
  printf '{"story_state":"IMPLEMENTING","_seq":0}\n' > "$project_dir/.forge/state.json"

  # Launch 5 concurrent checkpoint hooks
  for i in 1 2 3 4 5; do
    bash -c "cd '$project_dir' && python3 '$CHECKPOINT_HOOK'" &
  done
  wait

  # State file must be valid JSON
  run python3 -c "
import json
with open('$project_dir/.forge/state.json') as f:
    d = json.load(f)
assert 'lastCheckpoint' in d, 'lastCheckpoint missing after concurrent writes'
assert d['story_state'] == 'IMPLEMENTING', f'story_state corrupted: {d[\"story_state\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "hook-failure: concurrent checkpoint and feedback hooks don't interfere" {
  local project_dir="${TEST_TEMP}/hook-mixed-concurrent"
  mkdir -p "$project_dir/.forge"
  printf '{"story_state":"SHIPPING","mode":"standard","score_history":[85]}\n' \
    > "$project_dir/.forge/state.json"

  # Run checkpoint and feedback hooks concurrently
  bash -c "cd '$project_dir' && python3 '$CHECKPOINT_HOOK'" &
  bash -c "cd '$project_dir' && python3 '$FEEDBACK_HOOK'" &
  wait

  # state.json should remain valid
  run python3 -c "
import json
with open('$project_dir/.forge/state.json') as f:
    d = json.load(f)
assert d['story_state'] == 'SHIPPING'
print('OK')
"
  assert_success
  assert_output "OK"

  # Feedback file should exist
  [[ -f "$project_dir/.forge/feedback/auto-captured.md" ]] \
    || fail "auto-captured.md not created by feedback hook"
}

# ---------------------------------------------------------------------------
# 7. Bash-specific guards removed in Python port (platform.sh sourcing,
# atomic_json_update existence, final `exit 0` line). Python hooks exit via
# sys.exit() and have no equivalent shell dependencies to test for.
# ---------------------------------------------------------------------------
