#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  load '../hooks/helpers/mock-tool-input'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../shared/checks/l0-syntax/validate-syntax.sh"
}

@test "l0-syntax: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "l0-syntax: has bash shebang" {
  run head -1 "$HOOK_SCRIPT"
  assert_output --partial "bash"
}

@test "l0-syntax: exits 0 when FORGE_L0_ENABLED is false" {
  FORGE_L0_ENABLED=false TOOL_INPUT='{"file_path":"/tmp/test.ts"}' \
    run "$HOOK_SCRIPT"
  assert_success
}

@test "l0-syntax: handles missing TOOL_INPUT gracefully" {
  unset TOOL_INPUT
  run "$HOOK_SCRIPT"
  assert_success  # graceful degradation
}

@test "l0-syntax: logs failures to hook-failures.log format" {
  run grep -q '_log_failure' "$HOOK_SCRIPT"
  assert_success
}
