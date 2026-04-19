#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/post_tool_use_skill.py"
}

@test "checkpoint: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "checkpoint: exits 0 without state.json" {
  cd "$BATS_TEST_TMPDIR"
  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}
