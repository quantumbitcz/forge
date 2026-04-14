#!/usr/bin/env bats
# Scenario test: oscillation detection via convergence-engine-sim.sh.
# Validates that score oscillation patterns are correctly classified as
# PLATEAUED, REGRESSING, or IMPROVING by the convergence engine simulator.

load '../helpers/test-helpers'

SIM_SCRIPT="$PLUGIN_ROOT/shared/convergence-engine-sim.sh"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"

  FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

# ---------------------------------------------------------------------------
# 1. Oscillating scores around pass_threshold trigger PLATEAUED
# ---------------------------------------------------------------------------
@test "oscillation: score oscillating around pass_threshold triggers PLATEAUED convergence state" {
  run bash "$SIM_SCRIPT" \
    --scores "78,82,77,83,79,81" \
    --pass-threshold 80 \
    --oscillation-tolerance 5 \
    --plateau-patience 2
  assert_success

  # The last line should show phase=PLATEAUED (small smoothed delta over many cycles)
  local last_line
  last_line="$(echo "$output" | tail -1)"
  [[ "$last_line" == *"phase=PLATEAUED"* ]] \
    || fail "Expected PLATEAUED in last cycle, got: $last_line"
}

# ---------------------------------------------------------------------------
# 2. Oscillation above pass_threshold continues to perfection (no plateau)
# ---------------------------------------------------------------------------
@test "oscillation: steady improvement above pass_threshold continues without PLATEAUED" {
  # Steadily improving scores above threshold — large enough deltas that
  # |smoothed_delta| > plateau_threshold, so no plateau is detected.
  run bash "$SIM_SCRIPT" \
    --scores "82,85,88,91,94" \
    --pass-threshold 80 \
    --oscillation-tolerance 5 \
    --plateau-patience 3
  assert_success

  # Large positive deltas mean |smoothed| > 2 (default plateau_threshold),
  # so plateau_count stays at 0 throughout.
  local last_line
  last_line="$(echo "$output" | tail -1)"
  [[ "$last_line" != *"phase=PLATEAUED"* ]] \
    || fail "Expected no PLATEAUED for improving scores, got: $last_line"
}

# ---------------------------------------------------------------------------
# 3. Oscillation below pass_threshold triggers escalation
# ---------------------------------------------------------------------------
@test "oscillation: oscillation below pass_threshold triggers escalation" {
  run bash "$SIM_SCRIPT" \
    --scores "65,70,63,68,65,67" \
    --pass-threshold 80 \
    --oscillation-tolerance 5 \
    --plateau-patience 2
  assert_success

  # Scores oscillate below pass_threshold. With small deltas, should plateau.
  # PLATEAUED + below pass_threshold => decision=ESCALATE
  local last_line
  last_line="$(echo "$output" | tail -1)"
  [[ "$last_line" == *"decision=ESCALATE"* ]] \
    || fail "Expected ESCALATE for below-threshold plateau, got: $last_line"
}

# ---------------------------------------------------------------------------
# 4. oscillation_tolerance=0 means raw delta always exceeds tolerance => REGRESSING
# ---------------------------------------------------------------------------
@test "oscillation: oscillation_tolerance=0 triggers REGRESSING on any drop" {
  run bash "$SIM_SCRIPT" \
    --scores "78,82,78,82" \
    --pass-threshold 80 \
    --oscillation-tolerance 0 \
    --plateau-patience 2
  assert_success

  # With tolerance=0, a drop from 82->78 (delta=-4) exceeds tolerance of 0 => REGRESSING
  # Check that at least one line shows REGRESSING
  echo "$output" | grep -q "phase=REGRESSING" \
    || fail "Expected REGRESSING with oscillation_tolerance=0, got: $output"
}

# ---------------------------------------------------------------------------
# 5. oscillation_tolerance=20 is very permissive (no REGRESSING)
# ---------------------------------------------------------------------------
@test "oscillation: oscillation_tolerance=20 is very permissive" {
  run bash "$SIM_SCRIPT" \
    --scores "60,80,60,80" \
    --pass-threshold 80 \
    --oscillation-tolerance 20 \
    --plateau-patience 3
  assert_success

  # Delta of -20 is NOT > tolerance of 20, so no REGRESSING
  local has_regressing
  has_regressing=$(echo "$output" | grep -c "phase=REGRESSING" || true)
  [[ "$has_regressing" -eq 0 ]] \
    || fail "Expected no REGRESSING with tolerance=20, got: $output"
}

# ---------------------------------------------------------------------------
# 6. First cycle is exempt from plateau detection
# ---------------------------------------------------------------------------
@test "oscillation: first cycle exempt from plateau detection" {
  run bash "$SIM_SCRIPT" \
    --scores "80" \
    --pass-threshold 80 \
    --oscillation-tolerance 5 \
    --plateau-patience 2
  assert_success

  # Single score, first cycle -- no plateau possible
  local last_line
  last_line="$(echo "$output" | tail -1)"
  [[ "$last_line" == *"plateau_count=0"* ]] \
    || fail "Expected plateau_count=0 on first cycle, got: $last_line"
}
