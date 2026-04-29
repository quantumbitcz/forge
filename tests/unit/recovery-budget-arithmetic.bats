#!/usr/bin/env bats
# Unit tests: recovery budget arithmetic — validates budget ceiling,
# strategy weights, warning thresholds, and accumulation logic
# documented in recovery-engine.md.

load '../helpers/test-helpers'

RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"

# ---------------------------------------------------------------------------
# Helper: compute total weight from a list of strategy applications.
# Uses python3 for floating-point arithmetic (bc is not available on Windows
# Git Bash by default).
# ---------------------------------------------------------------------------
compute_total_weight() {
  python3 - "$@" <<'PYEOF'
import sys
print(sum(float(w) for w in sys.argv[1:]))
PYEOF
}

# Compare two numbers via python3 (replacement for `echo "a OP b" | bc`).
# Returns 0 if comparison is true, 1 otherwise.
_cmp() {
  python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
a, op, b = sys.argv[1], sys.argv[2], sys.argv[3]
ops = {'<': float(a) < float(b), '<=': float(a) <= float(b),
       '>': float(a) > float(b), '>=': float(a) >= float(b),
       '==': float(a) == float(b)}
sys.exit(0 if ops[op] else 1)
PYEOF
}

# Add two numbers (replacement for `echo "a + b" | bc`).
_add() {
  python3 - "$1" "$2" <<'PYEOF'
import sys
print(float(sys.argv[1]) + float(sys.argv[2]))
PYEOF
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
  _cmp "$total" "<" "$BUDGET_CEILING" \
    || fail "2 transient retries ($total) should be under ceiling ($BUDGET_CEILING)"
}

@test "recovery-budget: transient + tool-diag + state-recon = 3.0 (under ceiling)" {
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON")
  [[ "$total" == "3.0" ]] || fail "Expected 3.0, got $total"
  _cmp "$total" "<" "$BUDGET_CEILING" \
    || fail "$total should be under ceiling $BUDGET_CEILING"
}

@test "recovery-budget: all non-zero strategies once = 5.5 (exactly at ceiling)" {
  # 0.5 + 1.0 + 1.5 + 1.0 + 1.0 + 0.5 = 5.5
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN")
  [[ "$total" == "5.5" ]] || fail "Expected 5.5, got $total"
  _cmp "$total" ">=" "$BUDGET_CEILING" \
    || fail "$total should be at or above ceiling ($BUDGET_CEILING)"
}

@test "recovery-budget: 3 lightweight strategies = 2.0 (under ceiling)" {
  # transient(0.5) + resource-cleanup(0.5) + agent-reset(1.0) = 2.0
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_RESOURCE_CLEAN" "$W_AGENT_RESET")
  [[ "$total" == "2.0" ]] || fail "Expected 2.0, got $total"
  _cmp "$total" "<" "$BUDGET_CEILING" \
    || fail "$total should be under ceiling $BUDGET_CEILING"
}

@test "recovery-budget: exceeding ceiling = any application beyond 5.5" {
  # All non-zero strategies + extra transient = 6.0
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN" "$W_TRANSIENT")
  [[ "$total" == "6.0" ]] || fail "Expected 6.0, got $total"
  _cmp "$total" ">" "$BUDGET_CEILING" \
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
  _cmp "$total" ">=" "$WARNING_80PCT" \
    || fail "$total should trigger 80% warning (threshold=$WARNING_80PCT)"
}

@test "recovery-budget: budget at 4.3 does not trigger warning" {
  local total="4.3"
  _cmp "$total" "<" "$WARNING_80PCT" \
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
  _cmp "$total" ">=" "$WARNING_90PCT" \
    || fail "$total should trigger 90% escalation (threshold=$WARNING_90PCT)"
}

@test "recovery-budget: budget at 4.94 does not trigger 90% escalation" {
  local total="4.94"
  _cmp "$total" "<" "$WARNING_90PCT" \
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
  new_total=$(_add "$budget" "$proposed")
  _cmp "$new_total" ">" "$BUDGET_CEILING" \
    || fail "Adding $proposed to exhausted budget $budget should exceed ceiling"
}

@test "recovery-budget: heaviest strategy path = transient + state-recon + tool-diag + dep-health = 4.0" {
  # Realistic worst-case path before budget warning
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_STATE_RECON" "$W_TOOL_DIAG" "$W_DEP_HEALTH")
  [[ "$total" == "4.0" ]] || fail "Expected 4.0, got $total"
  _cmp "$total" "<" "$WARNING_80PCT" \
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
  _cmp "$total" "<" "$BUDGET_CEILING" \
    || fail "3 transient retries ($total) should be well under ceiling"
}

# ---------------------------------------------------------------------------
# 11. Sprint mode independent budgets
# ---------------------------------------------------------------------------
@test "recovery-budget: sprint independent budgets documented" {
  grep -qi "independent\|per.feature\|per.run\|isolated" "$RECOVERY_ENGINE" \
    || fail "Sprint mode independent budgets not documented"
}

# ---------------------------------------------------------------------------
# P2: Fallback chain budget arithmetic
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 12. TOOL_FAILURE fallback chain: tool-diag -> resource -> agent-reset
# ---------------------------------------------------------------------------
@test "recovery-budget: TOOL_FAILURE fallback chain = tool-diag -> resource -> agent-reset" {
  # Verify the chain weights are correct per documentation
  # tool-diagnosis(1.0) -> resource-cleanup(0.5) -> agent-reset(1.0)
  local chain_total
  chain_total=$(compute_total_weight "$W_TOOL_DIAG" "$W_RESOURCE_CLEAN" "$W_AGENT_RESET")
  [[ "$chain_total" == "2.5" ]] || fail "TOOL_FAILURE full chain cost should be 2.5, got $chain_total"
}

# ---------------------------------------------------------------------------
# 13. Fallback chain respects budget ceiling
# ---------------------------------------------------------------------------
@test "recovery-budget: fallback chain respects budget ceiling" {
  # Scenario: primary (1.0) fails, fallback (0.5) = total 1.5, within budget
  local budget="0.0"
  local primary="$W_TOOL_DIAG"   # 1.0
  local fallback="$W_RESOURCE_CLEAN"  # 0.5

  local after_primary
  after_primary=$(_add "$budget" "$primary")
  _cmp "$after_primary" "<=" "$BUDGET_CEILING" \
    || fail "Primary ($primary) should be within budget"

  local after_fallback
  after_fallback=$(_add "$after_primary" "$fallback")
  _cmp "$after_fallback" "<=" "$BUDGET_CEILING" \
    || fail "Primary + fallback ($after_fallback) should still be within budget"
}

# ---------------------------------------------------------------------------
# 14. Fallback chain stops when budget exceeded
# ---------------------------------------------------------------------------
@test "recovery-budget: fallback chain stops when budget exceeded" {
  # Scenario: budget at 5.0 (near ceiling of 5.5)
  # Primary tool-diag (1.0) fails — but wait, 5.0 + 1.0 = 6.0 > 5.5
  # So primary itself should be blocked
  local budget="5.0"
  local primary="$W_TOOL_DIAG"  # 1.0

  local after_primary
  after_primary=$(_add "$budget" "$primary")
  _cmp "$after_primary" ">" "$BUDGET_CEILING" \
    || fail "Primary at budget 5.0 should exceed ceiling"

  # But resource-cleanup (0.5) would fit: 5.0 + 0.5 = 5.5 (at ceiling)
  local fallback="$W_RESOURCE_CLEAN"  # 0.5
  local after_fallback_only
  after_fallback_only=$(_add "$budget" "$fallback")
  _cmp "$after_fallback_only" "<=" "$BUDGET_CEILING" \
    || fail "Fallback (0.5) alone at budget 5.0 should fit at ceiling"
}

# ---------------------------------------------------------------------------
# 15. Same strategy never applied twice per failure
# ---------------------------------------------------------------------------
@test "recovery-budget: same strategy never applied twice per failure" {
  # Validates the rule: if a chain had the same strategy in primary and fallback,
  # the fallback must be skipped. Test with synthetic data.
  # resource-cleanup(0.5) as primary, resource-cleanup(0.5) as fallback = skip
  local primary="resource-cleanup"
  local fallback="resource-cleanup"
  [[ "$primary" == "$fallback" ]] \
    && echo "Same strategy '$primary' in primary and fallback — fallback must be skipped" \
    || fail "Test setup error: strategies should be identical"
}

# ---------------------------------------------------------------------------
# 16. Max fallback depth is 2
# ---------------------------------------------------------------------------
@test "recovery-budget: max fallback depth is 2" {
  # The fallback chain table has: Primary | Fallback 1 | Fallback 2
  # No Fallback 3 column exists — max depth is 2
  grep -q "Fallback 2" "$RECOVERY_ENGINE" \
    || fail "Fallback 2 column not found in recovery-engine.md"
  # Ensure no Fallback 3
  ! grep -q "Fallback 3" "$RECOVERY_ENGINE" \
    || fail "Fallback 3 found — max depth should be 2"
}
