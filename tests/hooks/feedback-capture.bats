#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/feedback-capture.sh"
}

@test "feedback-capture: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "feedback-capture: exits 0 without .forge" {
  cd "$BATS_TEST_TMPDIR"
  run "$HOOK_SCRIPT"
  assert_success
}

@test "feedback-capture: writes to auto-captured.md" {
  run grep -q 'auto-captured' "$HOOK_SCRIPT"
  assert_success
}

@test "feedback-capture: includes file rotation logic" {
  run grep -qi 'rotat\|archive\|100.*[kK]' "$HOOK_SCRIPT"
  assert_success
}
