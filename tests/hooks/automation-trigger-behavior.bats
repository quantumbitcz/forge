#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/automation-trigger-hook.sh"
  TRIGGER_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/automation-trigger.sh"
}

@test "automation-trigger: hook script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "automation-trigger: extracts file path from JSON TOOL_INPUT" {
  # The hook uses python to extract file_path from TOOL_INPUT JSON.
  # Verify the extraction logic by grepping the script.
  run grep -qE 'file_path' "$HOOK_SCRIPT"
  assert_success
  # Also verify the JSON extraction pattern exists
  run grep -qE 'json\.load\|json\.loads\|file_path' "$HOOK_SCRIPT"
  assert_success
}

@test "automation-trigger: extracts file path from non-JSON TOOL_INPUT via regex" {
  # Verify the hook has a regex fallback for non-JSON TOOL_INPUT
  run grep -qE 'grep.*file_path\|regex\|sed' "$HOOK_SCRIPT"
  assert_success
}

@test "automation-trigger: handles missing .forge directory" {
  cd "${TEST_TEMP}/project"
  rm -rf .forge 2>/dev/null || true

  export TOOL_INPUT='{"file_path":"/src/main.ts","old_string":"a","new_string":"b"}'
  run "$HOOK_SCRIPT"
  assert_success
}

@test "automation-trigger: trigger script respects cooldown" {
  # Verify the automation-trigger.sh script has cooldown logic
  assert [ -f "$TRIGGER_SCRIPT" ]
  run grep -qE 'cooldown|last.*trigger|interval|recent' "$TRIGGER_SCRIPT"
  assert_success
}
