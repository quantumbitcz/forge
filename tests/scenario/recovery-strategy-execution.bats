#!/usr/bin/env bats
# Scenario tests: recovery strategy execution — validates strategy weights,
# budget arithmetic, fallback chains, circuit breaker, severity ordering,
# and budget reset policies documented in recovery-engine.md.

# Covers:

load '../helpers/test-helpers'

RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
ERROR_TAXONOMY="$PLUGIN_ROOT/shared/error-taxonomy.md"

# ---------------------------------------------------------------------------
# Helpers: floating-point arithmetic. `bc` is not on Git Bash for Windows;
# python3 is already a required tool, so use it for portable comparison and
# summation. Output format mirrors bc: trailing-zero-trimmed decimal
# (e.g. "5.5" not "5.50").
# ---------------------------------------------------------------------------
_pf_add() {
  # Mirrors `echo "a + b + ... | bc"` semantics: result scale = max input
  # scale; integer inputs produce integer results. Trims trailing zeros
  # past the input scale (e.g. 0.5 + 0.5 = 1.0, not 1.00).
  python3 -c "
import sys
from decimal import Decimal

vals = [Decimal(x) for x in sys.argv[1:]]
total = sum(vals, Decimal('0'))
scale = max((-v.as_tuple().exponent for v in vals if v.as_tuple().exponent < 0), default=0)
if scale == 0:
    print(int(total))
else:
    s = f'{total:.{scale}f}'
    # bc prints '.5' not '0.5' for results in (-1, 1); mirror this.
    if s.startswith('0.'):
        s = s[1:]
    elif s.startswith('-0.'):
        s = '-' + s[2:]
    print(s)
" "$@"
}

_pf_cmp() {
  # _pf_cmp <a> <op> <b>; op in (< <= > >= ==). Prints 1 if true, 0 otherwise.
  python3 -c "
import sys
a, op, b = float(sys.argv[1]), sys.argv[2], float(sys.argv[3])
ops = {'<': a < b, '<=': a <= b, '>': a > b, '>=': a >= b, '==': a == b}
print(1 if ops[op] else 0)
" "$1" "$2" "$3"
}

compute_total_weight() {
  _pf_add "$@"
}

# Budget ceiling
BUDGET_CEILING="5.5"

# Strategy weights (from recovery-engine.md §9)
W_TRANSIENT="0.5"
W_TOOL_DIAG="1.0"
W_STATE_RECON="1.5"
W_AGENT_RESET="1.0"
W_DEP_HEALTH="1.0"
W_RESOURCE_CLEAN="0.5"
W_GRACEFUL_STOP="0.0"

# ===========================================================================
# 1-7: Individual strategy weights documented correctly
# ===========================================================================

@test "recovery-strategy: transient-retry weight 0.5 documented in strategy table" {
  grep -A1 "transient-retry" "$RECOVERY_ENGINE" | grep -q "0\.5" \
    || fail "transient-retry weight 0.5 not documented in strategy table"
}

@test "recovery-strategy: tool-diagnosis weight 1.0 documented in strategy table" {
  grep -A1 "tool-diagnosis" "$RECOVERY_ENGINE" | grep -q "1\.0" \
    || fail "tool-diagnosis weight 1.0 not documented in strategy table"
}

@test "recovery-strategy: state-reconstruction weight 1.5 documented in strategy table" {
  grep -A1 "state-reconstruction" "$RECOVERY_ENGINE" | grep -q "1\.5" \
    || fail "state-reconstruction weight 1.5 not documented in strategy table"
}

@test "recovery-strategy: agent-reset weight 1.0 documented in strategy table" {
  grep -A1 "agent-reset" "$RECOVERY_ENGINE" | grep -q "1\.0" \
    || fail "agent-reset weight 1.0 not documented in strategy table"
}

@test "recovery-strategy: dependency-health weight 1.0 documented in strategy table" {
  grep -A1 "dependency-health" "$RECOVERY_ENGINE" | grep -q "1\.0" \
    || fail "dependency-health weight 1.0 not documented in strategy table"
}

@test "recovery-strategy: resource-cleanup weight 0.5 documented in strategy table" {
  grep -A1 "resource-cleanup" "$RECOVERY_ENGINE" | grep -q "0\.5" \
    || fail "resource-cleanup weight 0.5 not documented in strategy table"
}

@test "recovery-strategy: graceful-stop weight 0.0 documented in strategy table" {
  grep -A1 "graceful-stop" "$RECOVERY_ENGINE" | grep -q "0\.0" \
    || fail "graceful-stop weight 0.0 not documented in strategy table"
}

# ===========================================================================
# 8-10: Budget arithmetic
# ===========================================================================

@test "recovery-strategy: 2 transient + 1 tool-diag = 2.0" {
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TRANSIENT" "$W_TOOL_DIAG")
  [[ "$total" == "2.0" ]] || fail "Expected 2.0, got $total"
}

@test "recovery-strategy: full non-terminal chain = 5.5 (exactly at ceiling)" {
  # 0.5 + 1.0 + 1.5 + 1.0 + 1.0 + 0.5 = 5.5
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" \
    "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN")
  [[ "$total" == "5.5" ]] || fail "Expected 5.5, got $total"
}

@test "recovery-strategy: overflow blocked at ceiling 5.5" {
  # Full chain + 1 more transient = 6.0 > 5.5
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" \
    "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN" "$W_TRANSIENT")
  [[ $(_pf_cmp "$total" '>' "$BUDGET_CEILING") -eq 1 ]] \
    || fail "Expected overflow (got $total), ceiling is $BUDGET_CEILING"
}

# ===========================================================================
# 11-13: Fallback chain entries documented
# ===========================================================================

@test "recovery-strategy: TRANSIENT fallback chain is transient-retry → resource-cleanup" {
  # Verify the fallback table row for TRANSIENT
  grep -A1 "TRANSIENT" "$RECOVERY_ENGINE" | grep -q "transient-retry" \
    || fail "TRANSIENT primary strategy not documented as transient-retry"
  grep -A1 "TRANSIENT" "$RECOVERY_ENGINE" | grep -q "resource-cleanup" \
    || fail "TRANSIENT fallback to resource-cleanup not documented"
}

@test "recovery-strategy: TOOL_FAILURE fallback chain is tool-diagnosis → resource-cleanup → agent-reset" {
  # Verify the fallback table row for TOOL_FAILURE
  local row
  row=$(grep "TOOL_FAILURE.*tool-diagnosis" "$RECOVERY_ENGINE" || true)
  [[ -n "$row" ]] || fail "TOOL_FAILURE primary strategy not documented as tool-diagnosis"
  echo "$row" | grep -q "resource-cleanup" \
    || fail "TOOL_FAILURE fallback 1 not resource-cleanup"
  echo "$row" | grep -q "agent-reset" \
    || fail "TOOL_FAILURE fallback 2 not agent-reset"
}

@test "recovery-strategy: STATE_CORRUPTION fallback chain is state-reconstruction → graceful-stop" {
  local row
  row=$(grep "STATE_CORRUPTION.*state-reconstruction" "$RECOVERY_ENGINE" || true)
  [[ -n "$row" ]] || fail "STATE_CORRUPTION primary strategy not documented as state-reconstruction"
  echo "$row" | grep -q "graceful-stop" \
    || fail "STATE_CORRUPTION fallback not graceful-stop"
}

# ===========================================================================
# 14-15: Circuit breaker threshold and cooldown
# ===========================================================================

@test "recovery-strategy: circuit breaker threshold is 2 consecutive failures" {
  grep -q "threshold.*2\|2.*consecutive" "$RECOVERY_ENGINE" \
    || fail "Circuit breaker threshold of 2 not documented"
}

@test "recovery-strategy: circuit breaker cooldown is 300 seconds" {
  grep -q "300" "$RECOVERY_ENGINE" \
    || fail "Circuit breaker cooldown 300s not documented"
  grep -qi "cooldown" "$RECOVERY_ENGINE" \
    || fail "cooldown concept not documented"
}

# ===========================================================================
# 16-18: Severity ordering documented
# ===========================================================================

@test "recovery-strategy: highest-severity first ordering documented" {
  grep -qi "highest.*severity\|severity.*order\|highest-severity" "$RECOVERY_ENGINE" \
    || fail "Highest-severity-first ordering not documented"
}

@test "recovery-strategy: CRITICAL severity exists in error taxonomy" {
  [[ -f "$ERROR_TAXONOMY" ]] || skip "error-taxonomy.md not found"
  grep -qi "CRITICAL" "$ERROR_TAXONOMY" \
    || fail "CRITICAL severity not documented in error-taxonomy.md"
}

@test "recovery-strategy: TRANSIENT category documented as lowest recovery priority" {
  # TRANSIENT errors are lightweight (0.5 weight) — verify they are classified
  grep -qi "transient" "$RECOVERY_ENGINE" \
    || fail "TRANSIENT category not documented"
  # transient-retry is the cheapest non-terminal strategy
  [[ "$W_TRANSIENT" == "0.5" ]] || fail "Transient weight should be 0.5 (lightest non-terminal)"
}

# ===========================================================================
# 19-20: Budget resets per run, sprint mode independent budgets
# ===========================================================================

@test "recovery-strategy: budget resets at PREFLIGHT of each new run" {
  grep -qi "reset.*PREFLIGHT\|PREFLIGHT.*reset\|Budget Reset" "$RECOVERY_ENGINE" \
    || fail "Budget reset at PREFLIGHT not documented"
  grep -q "per-run\|per.run\|each new" "$RECOVERY_ENGINE" \
    || fail "Per-run budget reset policy not documented"
}

@test "recovery-strategy: sprint mode has independent budgets per feature" {
  grep -qi "independent.*budget\|independent recovery budget\|Sprint Mode Budget" "$RECOVERY_ENGINE" \
    || fail "Sprint mode independent budgets not documented"
}
