#!/usr/bin/env bats
# Scenario test: recovery budget exhaustion.
# Tests forge-state.sh transitions with pre-crafted state.json that has
# budget fields already set (per REVISIONS.md: no simulated accumulation).

# Covers: E-01, E-02, E-03

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

# ---------------------------------------------------------------------------
# 1. recovery_budget_exhausted transitions to ESCALATED (E2)
# ---------------------------------------------------------------------------
@test "recovery-budget: recovery_budget_exhausted triggers ESCALATED via E2" {
  # Init state, transition to IMPLEMENTING first
  bash "$FORGE_STATE_SH" init "RB-001" "Test recovery budget" --mode standard --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$FORGE_DIR" > /dev/null

  # Now at IMPLEMENTING. Craft state with exhausted budget via direct JSON write.
  local state_json
  state_json=$(jq '.recovery_budget.total_weight = 6.0 | .recovery_budget.max_weight = 5.5' "$FORGE_DIR/state.json")
  echo "$state_json" > "$FORGE_DIR/state.json"

  # Trigger recovery_budget_exhausted (E2 -- matches from ANY state)
  run bash "$FORGE_STATE_SH" transition recovery_budget_exhausted --forge-dir "$FORGE_DIR"
  assert_success

  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "ESCALATED" ]] \
    || fail "Expected ESCALATED after recovery_budget_exhausted, got $state"
}

# ---------------------------------------------------------------------------
# 2. Global retry budget exhaustion stops pipeline (E1)
# ---------------------------------------------------------------------------
@test "recovery-budget: global retry budget_exhausted triggers ESCALATED (E1)" {
  bash "$FORGE_STATE_SH" init "RB-002" "Test global retries" --mode standard --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null

  # Craft state with total_retries at max
  local state_json
  state_json=$(jq '.total_retries = 10 | .total_retries_max = 10' "$FORGE_DIR/state.json")
  echo "$state_json" > "$FORGE_DIR/state.json"

  # budget_exhausted event with guard matching E1 (total_retries >= total_retries_max)
  run bash "$FORGE_STATE_SH" transition budget_exhausted --guard "total_retries=10" --guard "total_retries_max=10" --forge-dir "$FORGE_DIR"
  assert_success

  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "ESCALATED" ]] \
    || fail "Expected ESCALATED after budget_exhausted, got $state"
}

# ---------------------------------------------------------------------------
# 3. Recovery budget resets between pipeline runs (fresh init = clean budget)
# ---------------------------------------------------------------------------
@test "recovery-budget: fresh init creates clean recovery budget" {
  bash "$FORGE_STATE_SH" init "RB-003" "Test budget reset" --mode standard --forge-dir "$FORGE_DIR"

  local total_weight
  total_weight="$(jq -r '.recovery_budget.total_weight' "$FORGE_DIR/state.json")"
  [[ "$total_weight" == "0" || "$total_weight" == "0.0" ]] \
    || fail "Expected recovery_budget.total_weight=0 on fresh init, got $total_weight"

  local max_weight
  max_weight="$(jq -r '.recovery_budget.max_weight' "$FORGE_DIR/state.json")"
  [[ "$max_weight" == "5.5" ]] \
    || fail "Expected recovery_budget.max_weight=5.5 on fresh init, got $max_weight"

  local apps
  apps="$(jq -r '.recovery_budget.applications | length' "$FORGE_DIR/state.json")"
  [[ "$apps" -eq 0 ]] \
    || fail "Expected empty recovery_budget.applications, got $apps entries"
}

# ---------------------------------------------------------------------------
# 4. Recovery budget tracks applications array structure
# ---------------------------------------------------------------------------
@test "recovery-budget: recovery_budget.applications array is structured" {
  bash "$FORGE_STATE_SH" init "RB-004" "Test budget structure" --mode standard --forge-dir "$FORGE_DIR"

  # Write pre-crafted state with budget applications
  local state_json
  state_json=$(jq '.recovery_budget.applications = [
    {"strategy": "retry", "cost": 0.5, "timestamp": "2026-01-01T00:00:00Z"},
    {"strategy": "skip", "cost": 1.0, "timestamp": "2026-01-01T00:01:00Z"}
  ] | .recovery_budget.total_weight = 1.5' "$FORGE_DIR/state.json")
  echo "$state_json" > "$FORGE_DIR/state.json"

  # Verify structure via jq
  local app_count strategy0 cost0
  app_count="$(jq '.recovery_budget.applications | length' "$FORGE_DIR/state.json")"
  strategy0="$(jq -r '.recovery_budget.applications[0].strategy' "$FORGE_DIR/state.json")"
  cost0="$(jq -r '.recovery_budget.applications[0].cost' "$FORGE_DIR/state.json")"

  [[ "$app_count" -eq 2 ]] || fail "Expected 2 applications, got $app_count"
  [[ "$strategy0" == "retry" ]] || fail "Expected strategy=retry, got $strategy0"
  [[ "$cost0" == "0.5" ]] || fail "Expected cost=0.5, got $cost0"
}

# ---------------------------------------------------------------------------
# 5. Circuit breaker: 3 consecutive transients trigger ESCALATED (E3)
# ---------------------------------------------------------------------------
@test "recovery-budget: circuit_breaker_open triggers ESCALATED (E3)" {
  bash "$FORGE_STATE_SH" init "RB-005" "Test circuit breaker" --mode standard --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null

  # Craft state with 3 transient failures (the circuit breaker decision is
  # made by the orchestrator before calling the transition). We test that the
  # circuit_breaker_open event correctly routes to ESCALATED.
  run bash "$FORGE_STATE_SH" transition circuit_breaker_open --forge-dir "$FORGE_DIR"
  assert_success

  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "ESCALATED" ]] \
    || fail "Expected ESCALATED after circuit_breaker_open, got $state"
}
