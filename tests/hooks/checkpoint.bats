#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/forge-checkpoint.sh"
}

@test "checkpoint: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "checkpoint: exits 0 without state.json" {
  cd "$BATS_TEST_TMPDIR"
  run "$HOOK_SCRIPT"
  assert_success
}

@test "checkpoint: sources platform.sh" {
  run grep -q 'platform.sh' "$HOOK_SCRIPT"
  assert_success
}

@test "checkpoint: uses atomic_json_update" {
  run grep -q 'atomic_json_update' "$HOOK_SCRIPT"
  assert_success
}
