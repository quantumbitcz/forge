#!/usr/bin/env bats
# Unit tests: hook failure scenarios — validates that Python hooks handle
# failure conditions gracefully: invalid JSON on stdin, missing state, and
# concurrent invocations.
#
# Behavior change vs. the old bash hooks: checkpoint no longer mutates
# state.json.lastCheckpoint (it appends to .forge/checkpoints.jsonl), and
# feedback-capture no longer writes auto-captured.md (it appends
# session_stop entries to .forge/events.jsonl). The old hook-failures log
# (.log suffix) and platform.sh atomic_json_update plumbing is gone.

load '../helpers/test-helpers'

CHECKPOINT_HOOK="$PLUGIN_ROOT/hooks/post_tool_use_skill.py"
FEEDBACK_HOOK="$PLUGIN_ROOT/hooks/stop.py"

# Helper: run a hook with CWD set to the given project dir
run_hook_in() {
  local hook="$1"
  local project_dir="$2"
  run bash -c "cd '$project_dir' && python3 '$hook' </dev/null"
}

# ---------------------------------------------------------------------------
# 1. Hook scripts exit 0 on invalid stdin or unexpected input
# ---------------------------------------------------------------------------

@test "hook-failure: checkpoint exits 0 on malformed stdin" {
  local project_dir="${TEST_TEMP}/hook-bad-stdin"
  mkdir -p "$project_dir/.forge"

  run bash -c "cd '$project_dir' && echo 'not json' | python3 '$CHECKPOINT_HOOK'"
  assert_success
}

@test "hook-failure: feedback exits 0 on malformed stdin" {
  local project_dir="${TEST_TEMP}/feedback-bad-stdin"
  mkdir -p "$project_dir/.forge"

  run bash -c "cd '$project_dir' && echo 'not json' | python3 '$FEEDBACK_HOOK'"
  assert_success
}

# ---------------------------------------------------------------------------
# 2. state.json is not touched by either Python hook — file stays byte-identical
# ---------------------------------------------------------------------------

@test "hook-failure: checkpoint does not modify state.json (Python port writes checkpoints.jsonl)" {
  local project_dir="${TEST_TEMP}/hook-preserve-state"
  mkdir -p "$project_dir/.forge"
  printf '{"story_state":"VERIFYING","mode":"bugfix","score_history":[60,75]}\n' \
    > "$project_dir/.forge/state.json"
  local before
  before="$(cat "$project_dir/.forge/state.json")"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  local after
  after="$(cat "$project_dir/.forge/state.json")"
  [[ "$before" == "$after" ]] \
    || fail "checkpoint hook modified state.json. Before: '$before' After: '$after'"
}

@test "hook-failure: checkpoint exits 0 on malformed state.json without corrupting it" {
  local project_dir="${TEST_TEMP}/hook-malformed"
  mkdir -p "$project_dir/.forge"
  printf 'this is { not valid json ]]]\n' > "$project_dir/.forge/state.json"
  local before
  before="$(cat "$project_dir/.forge/state.json")"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  local after
  after="$(cat "$project_dir/.forge/state.json")"
  [[ "$before" == "$after" ]] \
    || fail "state.json was modified: before='$before' after='$after'"
}

# ---------------------------------------------------------------------------
# 3. hooks.json declares timeouts
# ---------------------------------------------------------------------------

@test "hook-failure: hooks.json defines timeout for checkpoint hook" {
  local hooks_json="$PLUGIN_ROOT/hooks/hooks.json"
  [[ -f "$hooks_json" ]] || fail "hooks.json not found"

  run python3 - "$hooks_json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for group in d['hooks'].get('PostToolUse', []):
    if group.get('matcher') == 'Skill':
        for h in group.get('hooks', []):
            if 'post_tool_use_skill' in h.get('command', ''):
                assert 'timeout' in h, 'No timeout defined for checkpoint hook'
                assert h['timeout'] > 0, f'Timeout must be positive, got {h["timeout"]}'
                print(f'timeout={h["timeout"]}')
                exit(0)
print('NOTFOUND')
exit(1)
PYEOF
  assert_success
  [[ "$output" == *"timeout="* ]] || fail "Checkpoint hook timeout not found in hooks.json"
}

@test "hook-failure: hooks.json defines timeout for feedback hook" {
  local hooks_json="$PLUGIN_ROOT/hooks/hooks.json"
  [[ -f "$hooks_json" ]] || fail "hooks.json not found"

  run python3 - "$hooks_json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for group in d['hooks'].get('Stop', []):
    for h in group.get('hooks', []):
        if 'stop.py' in h.get('command', ''):
            assert 'timeout' in h, 'No timeout defined for feedback hook'
            assert h['timeout'] > 0, f'Timeout must be positive, got {h["timeout"]}'
            print(f'timeout={h["timeout"]}')
            exit(0)
print('NOTFOUND')
exit(1)
PYEOF
  assert_success
  [[ "$output" == *"timeout="* ]] || fail "Feedback hook timeout not found in hooks.json"
}

# ---------------------------------------------------------------------------
# 4. Empty / missing state files don't crash the hooks
# ---------------------------------------------------------------------------

@test "hook-failure: empty state.json does not crash checkpoint hook" {
  local project_dir="${TEST_TEMP}/hook-empty-state"
  mkdir -p "$project_dir/.forge"
  touch "$project_dir/.forge/state.json"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success
}

@test "hook-failure: empty state.json does not crash feedback hook" {
  local project_dir="${TEST_TEMP}/feedback-empty-state"
  mkdir -p "$project_dir/.forge"
  touch "$project_dir/.forge/state.json"

  run_hook_in "$FEEDBACK_HOOK" "$project_dir"
  assert_success
}

# ---------------------------------------------------------------------------
# 5. Concurrent invocations: checkpoints.jsonl and events.jsonl remain
#    well-formed (each line parses as JSON) even under contention.
# ---------------------------------------------------------------------------

@test "hook-failure: 5 concurrent checkpoint invocations produce well-formed checkpoints.jsonl" {
  local project_dir="${TEST_TEMP}/hook-concurrent"
  mkdir -p "$project_dir/.forge"

  for i in 1 2 3 4 5; do
    bash -c "cd '$project_dir' && echo '{\"tool_input\":{\"skill_name\":\"s$i\"}}' | python3 '$CHECKPOINT_HOOK'" &
  done
  wait

  local log="$project_dir/.forge/checkpoints.jsonl"
  assert [ -f "$log" ]
  # Every line must be valid JSON with a timestamp key.
  run python3 - "$log" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        entry = json.loads(line)
        assert 'timestamp' in entry
print('OK')
PYEOF
  assert_success
}

@test "hook-failure: concurrent checkpoint and feedback hooks write independent logs" {
  local project_dir="${TEST_TEMP}/hook-mixed-concurrent"
  mkdir -p "$project_dir/.forge"

  bash -c "cd '$project_dir' && echo '{}' | python3 '$CHECKPOINT_HOOK'" &
  bash -c "cd '$project_dir' && echo '{}' | python3 '$FEEDBACK_HOOK'" &
  wait

  assert [ -f "$project_dir/.forge/checkpoints.jsonl" ]
  assert [ -f "$project_dir/.forge/events.jsonl" ]
}
