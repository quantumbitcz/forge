#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/post_tool_use.py"
}

@test "automation-trigger: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "automation-trigger: always exits 0" {
  # Without .forge dir, should exit 0 immediately
  cd "$BATS_TEST_TMPDIR"
  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "automation-trigger: exits early without .forge directory" {
  cd "$BATS_TEST_TMPDIR"
  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}
