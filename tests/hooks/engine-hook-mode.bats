#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  ENGINE_SCRIPT="$BATS_TEST_DIRNAME/../../shared/checks/engine.sh"
}

@test "engine-hook: script exists and is executable" {
  assert [ -f "$ENGINE_SCRIPT" ]
  assert [ -x "$ENGINE_SCRIPT" ]
}

@test "engine-hook: accepts --hook flag" {
  run grep -q '\-\-hook' "$ENGINE_SCRIPT"
  assert_success
}

@test "engine-hook: has bash shebang" {
  run head -1 "$ENGINE_SCRIPT"
  assert_output --partial "bash"
}

@test "engine-hook: implements file-based locking" {
  run grep -qi 'flock\|lock\|mkdir.*lock' "$ENGINE_SCRIPT"
  assert_success
}

@test "engine-hook: logs failures to hook-failures.log" {
  run grep -q 'hook-failures' "$ENGINE_SCRIPT"
  assert_success
}
