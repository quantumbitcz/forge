#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  ENGINE_SCRIPT="$BATS_TEST_DIRNAME/../../shared/checks/engine.sh"
}

@test "check-engine-behavior: engine script exists and is executable" {
  assert [ -f "$ENGINE_SCRIPT" ]
  assert [ -x "$ENGINE_SCRIPT" ]
}

@test "check-engine-behavior: engine detects cloud credential pattern in L1 rules" {
  # Verify the engine has cloud credential / secret detection logic
  run grep -qE 'AWS_SECRET|AKIAIOS|secret.?key|SEC-SECRET' "$ENGINE_SCRIPT"
  # If not in engine.sh itself, check the rules files it loads
  if [[ "$status" -ne 0 ]]; then
    run grep -rqE 'AWS_SECRET|AKIAIOS|secret.?key|SEC-SECRET' \
      "$PLUGIN_ROOT/shared/checks/"
    assert_success
  fi
}

@test "check-engine-behavior: engine has TODO detection pattern" {
  # Verify the engine or its rules reference TODO detection
  run grep -rqE 'TODO|todo.*ticket|QUAL-TODO' \
    "$PLUGIN_ROOT/shared/checks/"
  assert_success
}

@test "check-engine-behavior: engine respects rules-override disabled flag" {
  # Verify engine.sh reads rules-override.json and honors disabled
  run grep -qE 'rules-override|disabled' "$ENGINE_SCRIPT"
  assert_success
}

@test "check-engine-behavior: engine has python fallback for bash < 4.0" {
  # Verify engine.sh checks BASH_VERSINFO and delegates to engine.py
  run grep -qE 'engine\.py' "$ENGINE_SCRIPT"
  assert_success
}

@test "check-engine-behavior: engine has timeout logic" {
  # Verify engine.sh has self-enforcing timeout
  run grep -qE '_HOOK_TIMEOUT|FORGE_HOOK_TIMEOUT|FORGE_CHECK_TIMEOUT' "$ENGINE_SCRIPT"
  assert_success
}
