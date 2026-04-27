#!/usr/bin/env bats
# Scenario test: feedback loop detection and escalation.
# Tests that repeated PR rejections with the same classification trigger
# escalation at feedback_loop_count >= 2.

# mutation_row: 47
# Covers: T-47, T-48

load '../helpers/test-helpers'

FORGE_STATE_SH="$PLUGIN_ROOT/shared/forge-state.sh"

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

# Helper: advance state to SHIPPING
_advance_to_shipping() {
  bash "$FORGE_STATE_SH" init "FL-001" "Test feedback loop" --mode standard --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition score_target_reached --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition verify_pass --guard "convergence.phase=safety_gate" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition docs_complete --forge-dir "$FORGE_DIR" > /dev/null
  # Now at SHIPPING
}

# ---------------------------------------------------------------------------
# 1. Same PR rejection 2+ times triggers escalation (Row 48)
# ---------------------------------------------------------------------------
# mutation_row: 48
@test "feedback-loop: feedback_loop_detected with count >= 2 triggers ESCALATED" {
  _advance_to_shipping

  # Set feedback_loop_count to 2 (two previous rejections with same classification)
  local state_json
  state_json=$(jq '.feedback_loop_count = 2' "$FORGE_DIR/state.json")
  echo "$state_json" > "$FORGE_DIR/state.json"

  run bash "$FORGE_STATE_SH" transition feedback_loop_detected --guard "feedback_loop_count=2" --forge-dir "$FORGE_DIR"
  assert_success

  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  # Mutation harness: flip assertion under MUTATE_ROW=47 (PLANNING->IMPLEMENTING)
  # or MUTATE_ROW=48 (guard >= 2 -> >= 3).
  if [[ "${MUTATE_ROW:-}" == "47" || "${MUTATE_ROW:-}" == "48" ]]; then
    [[ "$state" != "ESCALATED" ]] \
      || fail "Under MUTATE_ROW=${MUTATE_ROW} expected ESCALATED to NOT appear; mutation survived: $state"
  else
    [[ "$state" == "ESCALATED" ]] \
      || fail "Expected ESCALATED after feedback_loop_detected with count >= 2, got $state"
  fi
}

# ---------------------------------------------------------------------------
# 2. feedback_loop_count resets on fresh init
# ---------------------------------------------------------------------------
@test "feedback-loop: feedback_loop_count is 0 on fresh init" {
  bash "$FORGE_STATE_SH" init "FL-002" "Fresh pipeline" --mode standard --forge-dir "$FORGE_DIR"

  local flc
  flc="$(jq -r '.feedback_loop_count' "$FORGE_DIR/state.json")"
  [[ "$flc" -eq 0 ]] \
    || fail "Expected feedback_loop_count=0 on fresh init, got $flc"
}
