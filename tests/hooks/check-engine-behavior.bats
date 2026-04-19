#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  ENGINE_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/post_tool_use.py"
}

@test "check-engine-behavior: engine script exists and is executable" {
  assert [ -f "$ENGINE_SCRIPT" ]
  assert [ -x "$ENGINE_SCRIPT" ]
}

@test "check-engine-behavior: L1 rules contain cloud credential pattern" {
  # Cloud-credential detection now lives in the Python rule set under
  # hooks/_py/check_engine/ or the legacy rule files.
  run grep -rqE 'AWS_SECRET|AKIAIOS|secret.?key|SEC-SECRET' \
    "$PLUGIN_ROOT/shared/checks/" "$PLUGIN_ROOT/hooks/_py/check_engine/"
  assert_success
}

@test "check-engine-behavior: rule set has TODO detection pattern" {
  run grep -rqE 'TODO|todo.*ticket|QUAL-TODO' \
    "$PLUGIN_ROOT/shared/checks/" "$PLUGIN_ROOT/hooks/_py/check_engine/"
  assert_success
}
