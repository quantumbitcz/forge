#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/automation-trigger-hook.sh"
}

@test "automation-trigger: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "automation-trigger: always exits 0" {
  # Without .forge dir, should exit 0 immediately
  cd "$BATS_TEST_TMPDIR"
  run "$HOOK_SCRIPT"
  assert_success
}

@test "automation-trigger: has dual JSON/regex file_path extraction" {
  run grep -c 'file_path' "$HOOK_SCRIPT"
  assert_success
  [[ "$output" -ge 2 ]]  # At least 2 references (JSON + regex)
}

@test "automation-trigger: exits early without .forge directory" {
  cd "$BATS_TEST_TMPDIR"
  run "$HOOK_SCRIPT"
  assert_success
}
