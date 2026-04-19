#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/post_tool_use_agent.py"
}

@test "compact-check: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "compact-check: exits 0 without .forge directory" {
  cd "$BATS_TEST_TMPDIR"
  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}
