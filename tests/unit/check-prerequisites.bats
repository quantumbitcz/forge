#!/usr/bin/env bats
# Unit tests: check-prerequisites.sh — validates bash 4+ and python3.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/check-prerequisites.sh"

@test "check-prerequisites: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "check-prerequisites: passes on this machine (bash 4+ and python3 available)" {
  run bash "$SCRIPT"
  assert_success
  assert_output --partial "OK: all prerequisites met"
}

@test "check-prerequisites: reports bash version in output" {
  run bash "$SCRIPT"
  assert_success
  assert_output --partial "bash"
  assert_output --partial "python3"
}
