#!/usr/bin/env bats
# Scenario tests: pipeline simulation harness.
# Runs 10 YAML-driven scenarios through forge-sim.sh to validate
# end-to-end state machine behaviour.

load '../helpers/test-helpers'

SIM="$PLUGIN_ROOT/shared/forge-sim.sh"
FIXTURES="$PLUGIN_ROOT/tests/fixtures/sim"

@test "simulation: happy-path scenario" {
  run bash "$SIM" run "$FIXTURES/happy-path.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}

@test "simulation: convergence-improving scenario" {
  run bash "$SIM" run "$FIXTURES/convergence-improving.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}

@test "simulation: convergence-plateau scenario" {
  run bash "$SIM" run "$FIXTURES/convergence-plateau.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}

@test "simulation: convergence-regressing scenario" {
  run bash "$SIM" run "$FIXTURES/convergence-regressing.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}

@test "simulation: convergence-diminishing scenario" {
  run bash "$SIM" run "$FIXTURES/convergence-diminishing.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}

@test "simulation: pr-rejection-impl scenario" {
  run bash "$SIM" run "$FIXTURES/pr-rejection-impl.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}

@test "simulation: pr-rejection-design scenario" {
  run bash "$SIM" run "$FIXTURES/pr-rejection-design.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}

@test "simulation: budget-exhaustion scenario" {
  run bash "$SIM" run "$FIXTURES/budget-exhaustion.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}

@test "simulation: safety-gate-failure scenario" {
  run bash "$SIM" run "$FIXTURES/safety-gate-failure.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}

@test "simulation: dry-run scenario" {
  run bash "$SIM" run "$FIXTURES/dry-run.yaml" --forge-dir "$TEST_TEMP/project/.forge"
  assert_success
  assert_output --partial "PASS"
}
