#!/usr/bin/env bats
# Behavioral tests for hooks/stop.py — Python feedback-capture hook.
#
# Semantic change from the old bash hook: instead of writing a markdown log to
# .forge/feedback/auto-captured.md (with 100 KB rotation), the Python port
# appends a structured JSON line to .forge/events.jsonl with
#   {"kind": "session_stop", "timestamp", "transcript_path", "stop_hook_active"}.

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/stop.py"
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-feedback-behavior.XXXXXX")"
  mkdir -p "$TEST_TEMP/project"
}

teardown() {
  if [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]]; then
    rm -rf "$TEST_TEMP"
  fi
}

@test "feedback-capture: appends session_stop entry to events.jsonl" {
  local proj="${TEST_TEMP}/project"
  local forge_dir="${proj}/.forge"
  mkdir -p "$forge_dir"

  run bash -c "cd '$proj' && echo '{\"transcript_path\":\"/tmp/t.jsonl\",\"stop_hook_active\":true}' | python3 '$HOOK_SCRIPT'"
  assert_success
  assert [ -f "$forge_dir/events.jsonl" ]

  run python3 -c "
import json
with open('$forge_dir/events.jsonl') as f:
    entry = json.loads(f.readline())
assert entry['kind'] == 'session_stop'
assert entry['transcript_path'] == '/tmp/t.jsonl'
assert entry['stop_hook_active'] is True
assert 'timestamp' in entry
"
  assert_success
}

@test "feedback-capture: successive invocations append (do not rotate)" {
  local proj="${TEST_TEMP}/project"
  local forge_dir="${proj}/.forge"
  mkdir -p "$forge_dir"

  run bash -c "cd '$proj' && echo '{}' | python3 '$HOOK_SCRIPT'"
  assert_success
  run bash -c "cd '$proj' && echo '{}' | python3 '$HOOK_SCRIPT'"
  assert_success

  local count
  count=$(wc -l < "$forge_dir/events.jsonl" | tr -d ' ')
  [[ "$count" = "2" ]] || fail "expected 2 event lines, got $count"
}

@test "feedback-capture: handles missing .forge directory (exit 0)" {
  local proj="${TEST_TEMP}/project"
  # No .forge dir present
  run bash -c "cd '$proj' && echo '{}' | python3 '$HOOK_SCRIPT'"
  assert_success
  assert [ ! -f "$proj/.forge/events.jsonl" ]
}

@test "feedback-capture: handles malformed stdin gracefully (exit 0)" {
  local proj="${TEST_TEMP}/project"
  local forge_dir="${proj}/.forge"
  mkdir -p "$forge_dir"

  run bash -c "cd '$proj' && echo 'this is not valid json' | python3 '$HOOK_SCRIPT'"
  assert_success
  # Malformed payload → hook exits early, no events line appended.
  assert [ ! -f "$forge_dir/events.jsonl" ]
}
