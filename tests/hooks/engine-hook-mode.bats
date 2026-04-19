#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  ENGINE_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/post_tool_use.py"
}

@test "engine-hook: script exists and is executable" {
  assert [ -f "$ENGINE_SCRIPT" ]
  assert [ -x "$ENGINE_SCRIPT" ]
}

@test "engine-hook: has python3 shebang" {
  run head -1 "$ENGINE_SCRIPT"
  assert_output --partial "python3"
}
