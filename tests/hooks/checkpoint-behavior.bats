#!/usr/bin/env bats
# Behavioral tests for hooks/post_tool_use_skill.py — Python checkpoint hook.
#
# Semantic change from the old bash hook: the Python port no longer mutates
# state.json.lastCheckpoint. It appends a JSON line to .forge/checkpoints.jsonl
# with {timestamp, skill, tool}. Tests below assert that observable behavior.

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/post_tool_use_skill.py"
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-checkpoint-behavior.XXXXXX")"
  mkdir -p "$TEST_TEMP/project"
}

teardown() {
  if [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]]; then
    rm -rf "$TEST_TEMP"
  fi
}

@test "checkpoint: appends to checkpoints.jsonl when .forge exists" {
  local proj="${TEST_TEMP}/project"
  local forge_dir="${proj}/.forge"
  mkdir -p "$forge_dir"

  run bash -c "cd '$proj' && echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill_name\":\"forge-run\"}}' | python3 '$HOOK_SCRIPT'"
  assert_success

  assert [ -f "$forge_dir/checkpoints.jsonl" ]
  run grep -q '"skill": "forge-run"' "$forge_dir/checkpoints.jsonl"
  assert_success
}

@test "checkpoint: exits 0 when .forge is missing (no file created)" {
  local proj="${TEST_TEMP}/project"
  # No .forge dir at all
  run bash -c "cd '$proj' && echo '{}' | python3 '$HOOK_SCRIPT'"
  assert_success
  assert [ ! -f "$proj/.forge/checkpoints.jsonl" ]
}

@test "checkpoint: handles malformed stdin JSON gracefully (exit 0)" {
  local proj="${TEST_TEMP}/project"
  local forge_dir="${proj}/.forge"
  mkdir -p "$forge_dir"

  run bash -c "cd '$proj' && echo 'not json' | python3 '$HOOK_SCRIPT'"
  assert_success
  # Malformed payload → hook exits early, no checkpoint line appended.
  assert [ ! -f "$forge_dir/checkpoints.jsonl" ]
}

@test "checkpoint: subsequent invocations append (do not overwrite)" {
  local proj="${TEST_TEMP}/project"
  local forge_dir="${proj}/.forge"
  mkdir -p "$forge_dir"

  run bash -c "cd '$proj' && echo '{\"tool_input\":{\"skill_name\":\"a\"}}' | python3 '$HOOK_SCRIPT'"
  assert_success
  run bash -c "cd '$proj' && echo '{\"tool_input\":{\"skill_name\":\"b\"}}' | python3 '$HOOK_SCRIPT'"
  assert_success

  local count
  count=$(wc -l < "$forge_dir/checkpoints.jsonl" | tr -d ' ')
  [[ "$count" = "2" ]] || fail "expected 2 checkpoint lines, got $count"
}
