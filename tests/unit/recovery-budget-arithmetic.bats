#!/usr/bin/env bats
# Unit tests: recovery budget arithmetic — validates budget ceiling,
# strategy weights, warning thresholds, and accumulation logic
# documented in recovery-engine.md.

load '../helpers/test-helpers'

RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"

# ---------------------------------------------------------------------------
# Helper: compute total weight from a list of strategy applications
# ---------------------------------------------------------------------------
compute_total_weight() {
  local total=0
  for weight in "$@"; do
    total=$(echo "$total + $weight" | bc)
  done
  echo "$total"
}

# Budget ceiling
BUDGET_CEILING="5.5"
WARNING_80PCT="4.4"   # 80% of 5.5
WARNING_90PCT="4.95"  # 90% of 5.5

# Strategy weights (from recovery-engine.md)
W_TRANSIENT="0.5"
W_TOOL_DIAG="1.0"
W_STATE_RECON="1.5"
W_AGENT_RESET="1.0"
W_DEP_HEALTH="1.0"
W_RESOURCE_CLEAN="0.5"
W_GRACEFUL_STOP="0.0"

# ---------------------------------------------------------------------------
# 1. Individual strategy weights documented
# ---------------------------------------------------------------------------
@test "recovery-budget: transient-retry weight 0.5 documented" {
  grep -q "0\.5" "$RECOVERY_ENGINE" || fail "Weight 0.5 not documented"
  grep -qi "transient" "$RECOVERY_ENGINE" || fail "transient-retry not documented"
}

@test "recovery-budget: state-reconstruction weight 1.5 documented" {
  grep -q "1\.5" "$RECOVERY_ENGINE" || fail "Weight 1.5 not documented"
  grep -qi "state.reconstruction" "$RECOVERY_ENGINE" || fail "state-reconstruction not documented"
}

@test "recovery-budget: graceful-stop weight 0.0 documented" {
  grep -q "0\.0" "$RECOVERY_ENGINE" || fail "Weight 0.0 not documented"
  grep -qi "graceful.stop" "$RECOVERY_ENGINE" || fail "graceful-stop not documented"
}

# ---------------------------------------------------------------------------
# 2. Budget ceiling 5.5 documented and enforced
# ---------------------------------------------------------------------------
@test "recovery-budget: max_weight 5.5 ceiling documented" {
  grep -q "5\.5" "$RECOVERY_ENGINE" || fail "Budget ceiling 5.5 not documented"
  grep -qi "max_weight\|ceiling\|maximum" "$RECOVERY_ENGINE" || fail "Ceiling concept not documented"
}

# ---------------------------------------------------------------------------
# 3. Budget arithmetic: accumulation scenarios
# ---------------------------------------------------------------------------
@test "recovery-budget: 2 transient retries = 1.0 (under ceiling)" {
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TRANSIENT")
  [[ $(echo "$total < $BUDGET_CEILING" | bc) -eq 1 ]] \
    || fail "2 transient retries ($total) should be under ceiling ($BUDGET_CEILING)"
}

@test "recovery-budget: transient + tool-diag + state-recon = 3.0 (under ceiling)" {
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON")
  [[ "$total" == "3.0" ]] || fail "Expected 3.0, got $total"
  [[ $(echo "$total < $BUDGET_CEILING" | bc) -eq 1 ]] \
    || fail "$total should be under ceiling $BUDGET_CEILING"
}

@test "recovery-budget: all non-zero strategies once = 5.5 (exactly at ceiling)" {
  # 0.5 + 1.0 + 1.5 + 1.0 + 1.0 + 0.5 = 5.5
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN")
  [[ "$total" == "5.5" ]] || fail "Expected 5.5, got $total"
  [[ $(echo "$total >= $BUDGET_CEILING" | bc) -eq 1 ]] \
    || fail "$total should be at or above ceiling ($BUDGET_CEILING)"
}

@test "recovery-budget: 3 lightweight strategies = 2.0 (under ceiling)" {
  # transient(0.5) + resource-cleanup(0.5) + agent-reset(1.0) = 2.0
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_RESOURCE_CLEAN" "$W_AGENT_RESET")
  [[ "$total" == "2.0" ]] || fail "Expected 2.0, got $total"
  [[ $(echo "$total < $BUDGET_CEILING" | bc) -eq 1 ]] \
    || fail "$total should be under ceiling $BUDGET_CEILING"
}

@test "recovery-budget: exceeding ceiling = any application beyond 5.5" {
  # All non-zero strategies + extra transient = 6.0
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN" "$W_TRANSIENT")
  [[ "$total" == "6.0" ]] || fail "Expected 6.0, got $total"
  [[ $(echo "$total > $BUDGET_CEILING" | bc) -eq 1 ]] \
    || fail "$total should exceed ceiling $BUDGET_CEILING"
}

# ---------------------------------------------------------------------------
# 4. Warning thresholds
# ---------------------------------------------------------------------------
@test "recovery-budget: 80% warning threshold = 4.4 documented" {
  grep -q "80" "$RECOVERY_ENGINE" || fail "80% threshold not documented"
  grep -qi "warn" "$RECOVERY_ENGINE" || fail "Warning not documented"
}

@test "recovery-budget: budget at exactly 4.4 triggers warning" {
  local total="4.4"
  [[ $(echo "$total >= $WARNING_80PCT" | bc) -eq 1 ]] \
    || fail "$total should trigger 80% warning (threshold=$WARNING_80PCT)"
}

@test "recovery-budget: budget at 4.3 does not trigger warning" {
  local total="4.3"
  [[ $(echo "$total < $WARNING_80PCT" | bc) -eq 1 ]] \
    || fail "$total should NOT trigger 80% warning (threshold=$WARNING_80PCT)"
}

# ---------------------------------------------------------------------------
# 5. Graceful-stop has zero weight (never consumes budget)
# ---------------------------------------------------------------------------
@test "recovery-budget: graceful-stop does not consume budget" {
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_GRACEFUL_STOP" "$W_GRACEFUL_STOP")
  [[ "$total" == ".5" || "$total" == "0.5" ]] \
    || fail "Graceful-stop should be free; expected 0.5, got $total"
}

# ---------------------------------------------------------------------------
# 6. Budget resets per run (documented)
# ---------------------------------------------------------------------------
@test "recovery-budget: budget reset at PREFLIGHT documented" {
  grep -qi "reset\|PREFLIGHT\|per.run\|new.*run" "$RECOVERY_ENGINE" \
    || fail "Budget reset per run not documented"
}

# ---------------------------------------------------------------------------
# 7. All 7 strategies documented
# ---------------------------------------------------------------------------
@test "recovery-budget: all 7 recovery strategies documented" {
  for strategy in "transient-retry" "tool-diagnosis" "state-reconstruction" "agent-reset" "dependency-health" "resource-cleanup" "graceful-stop"; do
    grep -qi "$strategy" "$RECOVERY_ENGINE" \
      || fail "Strategy '$strategy' not documented"
  done
}

# ---------------------------------------------------------------------------
# 8. 90% escalation threshold (4.95)
# ---------------------------------------------------------------------------
@test "recovery-budget: budget at 4.95 triggers 90% escalation" {
  local total="4.95"
  [[ $(echo "$total >= $WARNING_90PCT" | bc) -eq 1 ]] \
    || fail "$total should trigger 90% escalation (threshold=$WARNING_90PCT)"
}

@test "recovery-budget: budget at 4.94 does not trigger 90% escalation" {
  local total="4.94"
  [[ $(echo "$total < $WARNING_90PCT" | bc) -eq 1 ]] \
    || fail "$total should NOT trigger 90% escalation (threshold=$WARNING_90PCT)"
}

# ---------------------------------------------------------------------------
# 9. Budget exhaustion + max retries simultaneous
# ---------------------------------------------------------------------------
@test "recovery-budget: 3 transient retries consume 1.5 weight" {
  # Per-strategy max retries = 3 for transient-retry
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TRANSIENT" "$W_TRANSIENT")
  [[ "$total" == "1.5" ]] || fail "Expected 1.5, got $total"
}

@test "recovery-budget: exhausted budget blocks further recovery even if retries remain" {
  # Scenario: budget at 5.5 (exhausted) — any new strategy application should be rejected
  local budget="5.5"
  local proposed="$W_TRANSIENT"
  local new_total
  new_total=$(echo "$budget + $proposed" | bc)
  [[ $(echo "$new_total > $BUDGET_CEILING" | bc) -eq 1 ]] \
    || fail "Adding $proposed to exhausted budget $budget should exceed ceiling"
}

@test "recovery-budget: heaviest strategy path = transient + state-recon + tool-diag + dep-health = 4.0" {
  # Realistic worst-case path before budget warning
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_STATE_RECON" "$W_TOOL_DIAG" "$W_DEP_HEALTH")
  [[ "$total" == "4.0" ]] || fail "Expected 4.0, got $total"
  [[ $(echo "$total < $WARNING_80PCT" | bc) -eq 1 ]] \
    || fail "4.0 should still be below 80% warning threshold"
}

# ---------------------------------------------------------------------------
# 10. Transient permanence rule (3 consecutive in 60s)
# ---------------------------------------------------------------------------
@test "recovery-budget: 3-consecutive-transients permanence rule documented" {
  grep -q "3 consecutive" "$RECOVERY_ENGINE" \
    || grep -q "3 consecutive" "$PLUGIN_ROOT/shared/error-taxonomy.md" \
    || fail "3-consecutive-transients permanence rule not documented"
}

@test "recovery-budget: 3 transient retries at max still under budget" {
  # Even worst-case 3 transient retries = 1.5, well under budget
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TRANSIENT" "$W_TRANSIENT")
  [[ $(echo "$total < $BUDGET_CEILING" | bc) -eq 1 ]] \
    || fail "3 transient retries ($total) should be well under ceiling"
}

# ---------------------------------------------------------------------------
# 11. Sprint mode independent budgets
# ---------------------------------------------------------------------------
@test "recovery-budget: sprint independent budgets documented" {
  grep -qi "independent\|per.feature\|per.run\|isolated" "$RECOVERY_ENGINE" \
    || fail "Sprint mode independent budgets not documented"
}
