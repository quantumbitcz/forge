#!/usr/bin/env bats
# Unit tests: check-prerequisites.sh — validates bash 4+ and python3
# with platform-adaptive install suggestions.

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
}

@test "check-prerequisites: reports detected platform in output" {
  run bash "$SCRIPT"
  assert_success
  assert_output --partial "platform:"
}

@test "check-prerequisites: uses inline OS detection (does not source platform.sh)" {
  run grep 'source.*platform\.sh' "$SCRIPT"
  assert_failure
}

@test "check-prerequisites: has _suggest_bash function for multi-platform hints" {
  run grep '_suggest_bash' "$SCRIPT"
  assert_success
}

@test "check-prerequisites: has _suggest_python function for multi-platform hints" {
  run grep '_suggest_python' "$SCRIPT"
  assert_success
}

@test "check-prerequisites: handles WSL detection" {
  run grep -c 'wsl' "$SCRIPT"
  assert_success
  [[ "${output}" -ge 2 ]]
}

@test "check-prerequisites: handles Git Bash detection" {
  run grep -c 'gitbash\|git-scm\|Git for Windows\|Git Bash' "$SCRIPT"
  assert_success
  [[ "${output}" -ge 2 ]]
}

@test "check-prerequisites: accepts python (not just python3)" {
  run bash -c "grep -q 'command -v python[^3]' '$SCRIPT' || grep -q \"command -v python'\" '$SCRIPT'"
  assert_success
}
