#!/usr/bin/env bats
# Scenario test: safety gate behavior between convergence phases.
# Tests that safety_gate transitions correctly reset phase state while
# preserving total_iterations and score_history.

load '../helpers/test-helpers'

FORGE_STATE_SH="$PLUGIN_ROOT/shared/forge-state.sh"
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

# Helper: advance state to VERIFYING in safety_gate phase
_advance_to_safety_gate_verifying() {
  bash "$FORGE_STATE_SH" init "SG-001" "Test safety gate" --mode standard --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$FORGE_DIR" > /dev/null
  # Now at VERIFYING, phase=correctness. Transition verify_pass to go to REVIEWING.
  bash "$FORGE_STATE_SH" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$FORGE_DIR" > /dev/null
  # Now at REVIEWING, phase=perfection. score_target_reached -> VERIFYING(safety_gate)
  bash "$FORGE_STATE_SH" transition score_target_reached --forge-dir "$FORGE_DIR" > /dev/null
  # Now at VERIFYING, phase=safety_gate
}

# ---------------------------------------------------------------------------
# 1. Safety gate pass sets safety_gate_passed=true and goes to DOCUMENTING (Row 27)
# ---------------------------------------------------------------------------
@test "safety-gate: verify_pass in safety_gate phase transitions to DOCUMENTING" {
  _advance_to_safety_gate_verifying

  # Verify we are in VERIFYING with phase=safety_gate
  local phase state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  phase="$(jq -r '.convergence.phase' "$FORGE_DIR/state.json")"
  [[ "$state" == "VERIFYING" ]] || fail "Expected VERIFYING, got $state"
  [[ "$phase" == "safety_gate" ]] || fail "Expected phase=safety_gate, got $phase"

  run bash "$FORGE_STATE_SH" transition verify_pass --guard "convergence.phase=safety_gate" --forge-dir "$FORGE_DIR"
  assert_success

  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "DOCUMENTING" ]] \
    || fail "Expected DOCUMENTING after safety gate pass, got $state"

  local sgp
  sgp="$(jq -r '.convergence.safety_gate_passed' "$FORGE_DIR/state.json")"
  [[ "$sgp" == "true" ]] \
    || fail "Expected safety_gate_passed=true, got $sgp"
}

# ---------------------------------------------------------------------------
# 2. Safety gate failure resets phase to correctness (Row 28)
# ---------------------------------------------------------------------------
@test "safety-gate: safety_gate_fail resets phase_iterations but preserves total_iterations" {
  _advance_to_safety_gate_verifying

  local total_before
  total_before="$(jq -r '.convergence.total_iterations' "$FORGE_DIR/state.json")"

  run bash "$FORGE_STATE_SH" transition safety_gate_fail --guard "safety_gate_failures=0" --forge-dir "$FORGE_DIR"
  assert_success

  local state phase phase_iter total_after
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  phase="$(jq -r '.convergence.phase' "$FORGE_DIR/state.json")"
  phase_iter="$(jq -r '.convergence.phase_iterations' "$FORGE_DIR/state.json")"
  total_after="$(jq -r '.convergence.total_iterations' "$FORGE_DIR/state.json")"

  [[ "$state" == "IMPLEMENTING" ]] \
    || fail "Expected IMPLEMENTING after safety_gate_fail, got $state"
  [[ "$phase" == "correctness" ]] \
    || fail "Expected phase reset to correctness, got $phase"
  [[ "$phase_iter" -eq 0 ]] \
    || fail "Expected phase_iterations=0 after safety gate fail, got $phase_iter"
  # total_iterations should be incremented by 1 (not reset)
  (( total_after == total_before + 1 )) \
    || fail "Expected total_iterations=$((total_before + 1)), got $total_after"
}

# ---------------------------------------------------------------------------
# 3. Safety gate failure does not reset score_history
# ---------------------------------------------------------------------------
@test "safety-gate: safety_gate_fail preserves score_history" {
  _advance_to_safety_gate_verifying

  # Pre-craft score_history with entries
  local state_json
  state_json=$(jq '.score_history = [65, 70, 75, 85, 90]' "$FORGE_DIR/state.json")
  echo "$state_json" > "$FORGE_DIR/state.json"

  run bash "$FORGE_STATE_SH" transition safety_gate_fail --guard "safety_gate_failures=0" --forge-dir "$FORGE_DIR"
  assert_success

  local history_len
  history_len="$(jq '.score_history | length' "$FORGE_DIR/state.json")"
  [[ "$history_len" -eq 5 ]] \
    || fail "Expected score_history to have 5 entries after safety gate fail, got $history_len"
}

# ---------------------------------------------------------------------------
# 4. Two safety gate failures escalate (Row 29)
# ---------------------------------------------------------------------------
@test "safety-gate: two safety_gate_fail events escalate to ESCALATED" {
  _advance_to_safety_gate_verifying

  # First failure (safety_gate_failures starts at 0)
  bash "$FORGE_STATE_SH" transition safety_gate_fail --guard "safety_gate_failures=0" --forge-dir "$FORGE_DIR" > /dev/null

  # Need to get back to VERIFYING with safety_gate phase for second failure.
  # After first fail, state is IMPLEMENTING with phase=correctness.
  # Fast-track back: implement_complete -> VERIFYING -> verify_pass(correctness) -> REVIEWING
  #   -> score_target_reached -> VERIFYING(safety_gate)
  bash "$FORGE_STATE_SH" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition score_target_reached --forge-dir "$FORGE_DIR" > /dev/null

  # Second failure (safety_gate_failures is now 1 from first fail)
  local sgf
  sgf="$(jq -r '.convergence.safety_gate_failures' "$FORGE_DIR/state.json")"

  run bash "$FORGE_STATE_SH" transition safety_gate_fail --guard "safety_gate_failures=$sgf" --forge-dir "$FORGE_DIR"
  assert_success

  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "ESCALATED" ]] \
    || fail "Expected ESCALATED after 2 safety gate failures, got $state"
}

# ---------------------------------------------------------------------------
# 5. PLATEAUED above pass_threshold triggers safety gate path via sim
# ---------------------------------------------------------------------------
@test "safety-gate: PLATEAUED above pass_threshold shows PASS_PLATEAUED decision" {
  run bash "$SIM_SCRIPT" \
    --scores "82,83,82,83,82,83" \
    --pass-threshold 80 \
    --plateau-patience 2 \
    --plateau-threshold 2
  assert_success

  # Scores above threshold with tiny smoothed delta => PLATEAUED with PASS_PLATEAUED
  local last_line
  last_line="$(echo "$output" | tail -1)"
  [[ "$last_line" == *"phase=PLATEAUED"* || "$last_line" == *"decision=PASS_PLATEAUED"* ]] \
    || fail "Expected PLATEAUED or PASS_PLATEAUED for above-threshold plateau, got: $last_line"
}
