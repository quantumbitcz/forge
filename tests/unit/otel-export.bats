#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  OTEL_SCRIPT="$BATS_TEST_DIRNAME/../../shared/forge-otel-export.sh"
}

@test "otel-export: script exists and is executable" {
  assert [ -f "$OTEL_SCRIPT" ]
  assert [ -x "$OTEL_SCRIPT" ]
}

@test "otel-export: exits 0 on missing state.json (graceful degradation)" {
  local empty_dir="${TEST_TEMP}/empty-forge"
  mkdir -p "$empty_dir"
  # No state.json in the forge dir — export should exit 0 with warning

  run bash "$OTEL_SCRIPT" export --endpoint "http://localhost:4318" --forge-dir "$empty_dir"
  assert_success
  assert_output --partial "WARNING"
}

@test "otel-export: exits with usage error when no command given" {
  run bash "$OTEL_SCRIPT"
  assert_failure
  assert_output --partial "Usage"
}

@test "otel-export: uses reasonable curl timeout" {
  # Verify the script configures a timeout for curl requests
  run grep -qE 'max-time|connect-timeout' "$OTEL_SCRIPT"
  assert_success
}
