#!/usr/bin/env bats
# Scenario test: preview gating at Stage 9 (SHIPPING).
# Per REVISIONS.md: Stage 8 = DOCUMENTING, Stage 9 = SHIPPING.
# Preview failures block SHIPPING progression. Fix loop exhaustion
# escalates to user.

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
  bash "$FORGE_STATE_SH" init "PG-001" "Test preview gating" --mode standard --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition score_target_reached --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition verify_pass --guard "convergence.phase=safety_gate" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition docs_complete --forge-dir "$FORGE_DIR" > /dev/null
  # Now at SHIPPING (Stage 9)
}

# ---------------------------------------------------------------------------
# 1. evidence_BLOCK at SHIPPING sends back to IMPLEMENTING (Row 42/43)
# ---------------------------------------------------------------------------
@test "preview-gating: evidence_BLOCK at Stage 9 SHIPPING blocks progression" {
  _advance_to_shipping

  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "SHIPPING" ]] || fail "Expected SHIPPING (Stage 9), got $state"

  # evidence_BLOCK with build failure sends back to IMPLEMENTING
  run bash "$FORGE_STATE_SH" transition evidence_BLOCK --guard "block_reason=build" --forge-dir "$FORGE_DIR"
  assert_success

  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "IMPLEMENTING" ]] \
    || fail "Expected IMPLEMENTING after evidence_BLOCK (build), got $state"

  # Phase should be reset to correctness for build/lint/test failures
  local phase
  phase="$(jq -r '.convergence.phase' "$FORGE_DIR/state.json")"
  [[ "$phase" == "correctness" ]] \
    || fail "Expected phase=correctness after evidence_BLOCK (build), got $phase"
}

# ---------------------------------------------------------------------------
# 2. Stale evidence with refresh count >= 3 escalates (Row 52)
# ---------------------------------------------------------------------------
@test "preview-gating: stale evidence with exhausted refresh loop escalates" {
  _advance_to_shipping

  # Set evidence_refresh_count to 3 (exhausted fix loop)
  local state_json
  state_json=$(jq '.evidence_refresh_count = 3' "$FORGE_DIR/state.json")
  echo "$state_json" > "$FORGE_DIR/state.json"

  # evidence_SHIP with stale evidence and exhausted refresh count => ESCALATED (Row 52)
  run bash "$FORGE_STATE_SH" transition evidence_SHIP --guard "evidence_fresh=false" --guard "evidence_refresh_count=3" --forge-dir "$FORGE_DIR"
  assert_success

  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "ESCALATED" ]] \
    || fail "Expected ESCALATED after exhausted evidence refresh loop, got $state"
}
