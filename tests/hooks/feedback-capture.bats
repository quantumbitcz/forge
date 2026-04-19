#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/stop.py"
}

@test "feedback-capture: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "feedback-capture: exits 0 without .forge" {
  cd "$BATS_TEST_TMPDIR"
  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}
