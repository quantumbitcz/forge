#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../shared/forge-compact-check.sh"
}

@test "compact-check: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "compact-check: exits 0 without .forge directory" {
  cd "$BATS_TEST_TMPDIR"
  run "$HOOK_SCRIPT"
  assert_success
}

@test "compact-check: sources platform.sh" {
  run grep -q 'platform.sh' "$HOOK_SCRIPT"
  assert_success
}

@test "compact-check: writes to compact-suggestion file" {
  run grep -q 'compact-suggestion' "$HOOK_SCRIPT"
  assert_success
}
