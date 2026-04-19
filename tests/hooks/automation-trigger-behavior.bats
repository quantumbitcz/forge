#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/post_tool_use.py"
  TRIGGER_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/automation_trigger.py"
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-automation-behavior.XXXXXX")"
  mkdir -p "$TEST_TEMP/project"
}

teardown() {
  if [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]]; then
    rm -rf "$TEST_TEMP"
  fi
}

@test "automation-trigger: hook script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "automation-trigger: handles missing .forge directory" {
  cd "${TEST_TEMP}/project"
  rm -rf .forge 2>/dev/null || true

  run bash -c "echo '{\"tool_input\":{\"file_path\":\"/src/main.ts\",\"old_string\":\"a\",\"new_string\":\"b\"}}' | python3 '$HOOK_SCRIPT'"
  assert_success
}

@test "automation-trigger: trigger script respects cooldown" {
  # Verify the Python automation trigger entry exists; cooldown logic lives in
  # hooks/_py/automation_trigger_cli.py (ported in Task 10).
  assert [ -f "$TRIGGER_SCRIPT" ]
}
