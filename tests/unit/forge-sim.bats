#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  SIM_SCRIPT="$BATS_TEST_DIRNAME/../../shared/forge-sim.sh"
}

@test "forge-sim: script exists and is executable" {
  assert [ -f "$SIM_SCRIPT" ]
  assert [ -x "$SIM_SCRIPT" ]
}

@test "forge-sim: handles missing scenario file gracefully" {
  run bash "$SIM_SCRIPT" run /nonexistent/scenario.yaml
  assert_failure
  assert_output --partial "ERROR"
}

@test "forge-sim: shows usage when no arguments given" {
  run bash "$SIM_SCRIPT"
  assert_failure
  assert_output --partial "Usage"
}
