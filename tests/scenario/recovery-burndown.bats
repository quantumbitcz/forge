#!/usr/bin/env bats
# Scenario tests: recovery engine burndown — validates end-to-end recovery
# budget exhaustion, fallback chain execution, warning thresholds, transient
# permanence rule, and budget reset policies documented in recovery-engine.md
# and error-taxonomy.md.

# Covers:

load '../helpers/test-helpers'

RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
ERROR_TAXONOMY="$PLUGIN_ROOT/shared/error-taxonomy.md"
STATE_WRITER="$PLUGIN_ROOT/shared/forge-state-write.sh"

# ---------------------------------------------------------------------------
# Helpers: floating-point arithmetic. `bc` is not on Git Bash for Windows;
# python3 is already required, so use it. Output format mirrors bc:
# trailing-zero-trimmed decimal (e.g. "5.5" not "5.50").
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

# Helper: compute total weight from a list of strategy applications
compute_total_weight() {
  _pf_add "$@"
}

# Helper: create state.json with recovery budget at a given weight.
# Path passed via argv (sys.argv[1]); weight + applications passed via env
# vars so MSYS auto-conversion of the path (which interpolating breaks under
# native Windows Python) is preserved.
create_state_with_budget() {
  local forge_dir="$1"
  local total_weight="$2"
  local apps_json="${3:-[]}"
  mkdir -p "$forge_dir"
  FORGE_TOTAL_WEIGHT="$total_weight" FORGE_APPS_JSON="$apps_json" \
    python3 - "$forge_dir/state.json" <<'PY'
import json
import os
import sys
from pathlib import Path

state = {
    'version': '1.5.0',
    'story_state': 'IMPLEMENTING',
    'mode': 'standard',
    '_seq': 0,
    'recovery_budget': {
        'total_weight': float(os.environ['FORGE_TOTAL_WEIGHT']),
        'max_weight': 5.5,
        'applications': json.loads(os.environ['FORGE_APPS_JSON']),
    },
    'recovery': {
        'total_failures': 0,
        'total_recoveries': 0,
        'degraded_capabilities': [],
        'failures': [],
        'budget_warning_issued': False,
    },
}
with Path(sys.argv[1]).open('w') as f:
    json.dump(state, f, indent=2)
PY
}

# Budget ceiling and strategy weights (from recovery-engine.md section 9)
BUDGET_CEILING="5.5"
WARNING_80PCT="4.4"
WARNING_90PCT="4.95"

W_TRANSIENT="0.5"
W_TOOL_DIAG="1.0"
W_STATE_RECON="1.5"
W_AGENT_RESET="1.0"
W_DEP_HEALTH="1.0"
W_RESOURCE_CLEAN="0.5"
W_GRACEFUL_STOP="0.0"

# ===========================================================================
# 1. Apply all 7 recovery strategies in sequence
# ===========================================================================

@test "recovery-burndown: all 7 strategies documented with correct weights" {
  local strategies=(
    "transient-retry:0.5"
    "tool-diagnosis:1.0"
    "state-reconstruction:1.5"
    "agent-reset:1.0"
    "dependency-health:1.0"
    "resource-cleanup:0.5"
    "graceful-stop:0.0"
  )

  for entry in "${strategies[@]}"; do
    local name="${entry%%:*}"
    local weight="${entry##*:}"
    grep -qi "$name" "$RECOVERY_ENGINE" \
      || fail "Strategy '$name' not documented in recovery-engine.md"
    grep -q "$weight" "$RECOVERY_ENGINE" \
      || fail "Weight '$weight' for strategy '$name' not documented"
  done
}

@test "recovery-burndown: applying all 7 strategies in sequence produces correct cumulative weights" {
  # Simulate applying each strategy one at a time and tracking cumulative weight
  local running_total=0.0
  local expected_totals=("0.5" "1.5" "3.0" "4.0" "5.0" "5.5" "5.5")
  local weights=("$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN" "$W_GRACEFUL_STOP")

  for i in 0 1 2 3 4 5 6; do
    running_total=$(_pf_add "$running_total" "${weights[$i]}")
    local expected="${expected_totals[$i]}"
    # bc may return ".5" instead of "0.5" — normalize
    local normalized
    normalized=$(echo "$running_total" | sed 's/^\./0./')
    [[ "$normalized" == "$expected" ]] \
      || fail "After strategy $((i+1)), expected cumulative weight $expected, got $normalized"
  done
}

@test "recovery-burndown: all 7 strategy .md files exist in strategies directory" {
  local strategies_dir="$PLUGIN_ROOT/shared/recovery/strategies"
  local expected_files=(
    "transient-retry.md"
    "tool-diagnosis.md"
    "state-reconstruction.md"
    "agent-reset.md"
    "dependency-health.md"
    "resource-cleanup.md"
    "graceful-stop.md"
  )

  for file in "${expected_files[@]}"; do
    [[ -f "$strategies_dir/$file" ]] \
      || fail "Strategy file $file not found in $strategies_dir"
  done
}

# ===========================================================================
# 2. Budget exhaustion stops further recovery attempts
# ===========================================================================

@test "recovery-burndown: budget at 5.5 blocks any non-terminal strategy" {
  # At ceiling: any non-zero weight strategy should be blocked
  local budget="5.5"
  for weight in "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN"; do
    local new_total
    new_total=$(_pf_add "$budget" "$weight")
    [[ $(_pf_cmp "$new_total" '>' "$BUDGET_CEILING") -eq 1 ]] \
      || fail "Strategy with weight $weight should be blocked at budget $budget (would be $new_total)"
  done
}

@test "recovery-burndown: budget exhaustion documented as BUDGET_EXHAUSTED error" {
  grep -qi "BUDGET_EXHAUSTED" "$RECOVERY_ENGINE" \
    || fail "BUDGET_EXHAUSTED error not documented in recovery-engine.md"
}

@test "recovery-burndown: graceful-stop still allowed at exhausted budget" {
  # graceful-stop has weight 0.0, so it should always be allowed
  local budget="5.5"
  local new_total
  new_total=$(_pf_add "$budget" "$W_GRACEFUL_STOP")
  [[ $(_pf_cmp "$new_total" '<=' "$BUDGET_CEILING") -eq 1 ]] \
    || fail "graceful-stop (weight 0.0) should be allowed even at exhausted budget"
}

# ===========================================================================
# 3. Fallback chain execution (primary fails, fallback succeeds)
# ===========================================================================

@test "recovery-burndown: TRANSIENT fallback chain cost = 0.5 + 0.5 = 1.0" {
  # TRANSIENT: transient-retry(0.5) -> resource-cleanup(0.5)
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_RESOURCE_CLEAN")
  [[ "$total" == "1.0" ]] || fail "Expected TRANSIENT full chain cost 1.0, got $total"
}

@test "recovery-burndown: TOOL_FAILURE fallback chain cost = 1.0 + 0.5 + 1.0 = 2.5" {
  # TOOL_FAILURE: tool-diagnosis(1.0) -> resource-cleanup(0.5) -> agent-reset(1.0)
  local total
  total=$(compute_total_weight "$W_TOOL_DIAG" "$W_RESOURCE_CLEAN" "$W_AGENT_RESET")
  [[ "$total" == "2.5" ]] || fail "Expected TOOL_FAILURE full chain cost 2.5, got $total"
}

@test "recovery-burndown: AGENT_FAILURE fallback chain cost = 1.0 + 0.5 = 1.5" {
  # AGENT_FAILURE: agent-reset(1.0) -> resource-cleanup(0.5)
  local total
  total=$(compute_total_weight "$W_AGENT_RESET" "$W_RESOURCE_CLEAN")
  [[ "$total" == "1.5" ]] || fail "Expected AGENT_FAILURE full chain cost 1.5, got $total"
}

@test "recovery-burndown: STATE_CORRUPTION fallback chain cost = 1.5 + 0.0 = 1.5" {
  # STATE_CORRUPTION: state-reconstruction(1.5) -> graceful-stop(0.0)
  local total
  total=$(compute_total_weight "$W_STATE_RECON" "$W_GRACEFUL_STOP")
  [[ "$total" == "1.5" ]] || fail "Expected STATE_CORRUPTION full chain cost 1.5, got $total"
}

@test "recovery-burndown: EXTERNAL_DEPENDENCY fallback chain cost = 1.0 + 0.5 = 1.5" {
  # EXTERNAL_DEPENDENCY: dependency-health(1.0) -> transient-retry(0.5)
  local total
  total=$(compute_total_weight "$W_DEP_HEALTH" "$W_TRANSIENT")
  [[ "$total" == "1.5" ]] || fail "Expected EXTERNAL_DEPENDENCY full chain cost 1.5, got $total"
}

@test "recovery-burndown: RESOURCE_EXHAUSTION fallback chain cost = 0.5 + 1.0 = 1.5" {
  # RESOURCE_EXHAUSTION: resource-cleanup(0.5) -> agent-reset(1.0)
  local total
  total=$(compute_total_weight "$W_RESOURCE_CLEAN" "$W_AGENT_RESET")
  [[ "$total" == "1.5" ]] || fail "Expected RESOURCE_EXHAUSTION full chain cost 1.5, got $total"
}

@test "recovery-burndown: UNRECOVERABLE has no fallback (graceful-stop only)" {
  local row
  row=$(grep "UNRECOVERABLE.*graceful-stop" "$RECOVERY_ENGINE" || true)
  [[ -n "$row" ]] || fail "UNRECOVERABLE row not found in fallback table"
  # Verify no fallback strategies listed (should have dashes/empty)
  echo "$row" | grep -q "| --- |$\|| — |$" \
    || echo "$row" | grep -qv "transient-retry\|tool-diagnosis\|state-reconstruction\|agent-reset\|dependency-health\|resource-cleanup" \
    || fail "UNRECOVERABLE should have no fallback strategies"
}

@test "recovery-burndown: fallback stops when budget would be exceeded" {
  # Scenario: budget at 5.0, TOOL_FAILURE primary tool-diagnosis(1.0) exceeds ceiling
  local budget="5.0"
  local primary="$W_TOOL_DIAG"  # 1.0
  local new_total
  new_total=$(_pf_add "$budget" "$primary")
  [[ $(_pf_cmp "$new_total" '>' "$BUDGET_CEILING") -eq 1 ]] \
    || fail "Primary should exceed budget at $budget"

  # But Fallback 1 resource-cleanup(0.5) fits: 5.0 + 0.5 = 5.5
  local fallback1="$W_RESOURCE_CLEAN"
  local fb1_total
  fb1_total=$(_pf_add "$budget" "$fallback1")
  [[ $(_pf_cmp "$fb1_total" '<=' "$BUDGET_CEILING") -eq 1 ]] \
    || fail "Fallback 1 (resource-cleanup, 0.5) should fit at budget $budget"

  # Fallback 2 agent-reset(1.0) would not fit after fb1: 5.5 + 1.0 = 6.5
  local fb2_total
  fb2_total=$(_pf_add "$fb1_total" "$W_AGENT_RESET")
  [[ $(_pf_cmp "$fb2_total" '>' "$BUDGET_CEILING") -eq 1 ]] \
    || fail "Fallback 2 should exceed budget after fallback 1 applied"
}

# ===========================================================================
# 4. Budget threshold warnings at 80% and 90%
# ===========================================================================

@test "recovery-burndown: 80% warning threshold (4.4) documented" {
  grep -q "80" "$RECOVERY_ENGINE" || fail "80% threshold not documented"
  grep -q "4\.4" "$RECOVERY_ENGINE" || fail "4.4 threshold value not documented"
  grep -qi "warn" "$RECOVERY_ENGINE" || fail "Warning concept not documented"
}

@test "recovery-burndown: budget at 4.3 does not trigger 80% warning" {
  local total="4.3"
  [[ $(_pf_cmp "$total" '<' "$WARNING_80PCT") -eq 1 ]] \
    || fail "Budget $total should be below 80% warning threshold ($WARNING_80PCT)"
}

@test "recovery-burndown: budget at exactly 4.4 triggers 80% warning" {
  local total="4.4"
  [[ $(_pf_cmp "$total" '>=' "$WARNING_80PCT") -eq 1 ]] \
    || fail "Budget $total should trigger 80% warning (threshold=$WARNING_80PCT)"
}

@test "recovery-burndown: 90% escalation threshold (4.95) documented" {
  grep -q "90" "$RECOVERY_ENGINE" || fail "90% threshold not documented"
  grep -q "4\.95" "$RECOVERY_ENGINE" || fail "4.95 threshold value not documented"
}

@test "recovery-burndown: budget at 4.94 does not trigger 90% escalation" {
  local total="4.94"
  [[ $(_pf_cmp "$total" '<' "$WARNING_90PCT") -eq 1 ]] \
    || fail "Budget $total should NOT trigger 90% escalation (threshold=$WARNING_90PCT)"
}

@test "recovery-burndown: budget at 4.95 triggers 90% escalation" {
  local total="4.95"
  [[ $(_pf_cmp "$total" '>=' "$WARNING_90PCT") -eq 1 ]] \
    || fail "Budget $total should trigger 90% escalation (threshold=$WARNING_90PCT)"
}

@test "recovery-burndown: budget_warning_issued field documented in schema" {
  grep -q "budget_warning_issued" "$RECOVERY_ENGINE" \
    || fail "budget_warning_issued field not documented"
}

# ===========================================================================
# 5. 3 consecutive transients in 60s triggers non-recoverable
# ===========================================================================

@test "recovery-burndown: 3-consecutive-transients permanence rule documented" {
  grep -q "3 consecutive" "$RECOVERY_ENGINE" \
    || grep -q "3 consecutive" "$ERROR_TAXONOMY" \
    || fail "3-consecutive-transients permanence rule not documented"
}

@test "recovery-burndown: 60-second window for transient permanence documented" {
  grep -q "60" "$ERROR_TAXONOMY" \
    || grep -q "60" "$RECOVERY_ENGINE" \
    || fail "60-second window for transient permanence not documented"
}

@test "recovery-burndown: 3 transient retries consume 1.5 weight total" {
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TRANSIENT" "$W_TRANSIENT")
  [[ "$total" == "1.5" ]] || fail "Expected 1.5, got $total"
  # 1.5 is well within budget ceiling
  [[ $(_pf_cmp "$total" '<' "$BUDGET_CEILING") -eq 1 ]] \
    || fail "3 transient retries ($total) should be within budget ($BUDGET_CEILING)"
}

@test "recovery-burndown: NETWORK_UNAVAILABLE maps to TRANSIENT category" {
  grep -A2 "NETWORK_UNAVAILABLE" "$RECOVERY_ENGINE" | grep -qi "transient" \
    || fail "NETWORK_UNAVAILABLE should map to TRANSIENT recovery category"
}

@test "recovery-burndown: permanent reclassification prevents further budget consumption" {
  # After 3 consecutive transients, no more recovery budget should be consumed
  # for that endpoint. The error becomes non-recoverable (graceful-stop, weight 0.0).
  # Verify: 3 transient retries (1.5) + graceful stop (0.0) = 1.5 total
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TRANSIENT" "$W_TRANSIENT" "$W_GRACEFUL_STOP")
  [[ "$total" == "1.5" ]] || fail "Expected 1.5 after permanence, got $total"
}

# ===========================================================================
# 6. Recovery budget resets at PREFLIGHT
# ===========================================================================

@test "recovery-burndown: budget reset at PREFLIGHT documented" {
  grep -qi "reset.*PREFLIGHT\|PREFLIGHT.*reset\|Budget Reset" "$RECOVERY_ENGINE" \
    || fail "Budget reset at PREFLIGHT not documented"
}

@test "recovery-burndown: budget is per-run not per-session" {
  grep -q "per-run\|per.run\|each new" "$RECOVERY_ENGINE" \
    || fail "Per-run budget reset policy not documented"
}

@test "recovery-burndown: state.json recovery_budget schema has total_weight and max_weight" {
  local forge_dir="${TEST_TEMP}/budget-reset/.forge"
  create_state_with_budget "$forge_dir" 3.5

  run python3 - "$forge_dir/state.json" <<'PY'
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as f:
    d = json.load(f)
rb = d['recovery_budget']
assert 'total_weight' in rb, 'Missing total_weight'
assert 'max_weight' in rb, 'Missing max_weight'
assert rb['max_weight'] == 5.5, f"max_weight should be 5.5, got {rb['max_weight']}"
assert rb['total_weight'] == 3.5, f"total_weight should be 3.5, got {rb['total_weight']}"
print('OK')
PY
  assert_success
  assert_output "OK"
}

@test "recovery-burndown: simulated budget reset zeros total_weight" {
  local forge_dir="${TEST_TEMP}/budget-reset-sim/.forge"
  create_state_with_budget "$forge_dir" 4.5 '[{"strategy":"transient-retry","weight":0.5},{"strategy":"tool-diagnosis","weight":1.0}]'

  # Simulate PREFLIGHT budget reset
  python3 - "$forge_dir/state.json" <<'PY'
import json
import sys
from pathlib import Path

p = Path(sys.argv[1])
with p.open() as f:
    d = json.load(f)
d['recovery_budget']['total_weight'] = 0.0
d['recovery_budget']['applications'] = []
d['recovery']['budget_warning_issued'] = False
with p.open('w') as f:
    json.dump(d, f, indent=2)
PY

  run python3 - "$forge_dir/state.json" <<'PY'
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as f:
    d = json.load(f)
assert d['recovery_budget']['total_weight'] == 0.0, 'Budget not reset'
assert d['recovery_budget']['applications'] == [], 'Applications not cleared'
assert d['recovery']['budget_warning_issued'] is False, 'Warning not cleared'
print('OK')
PY
  assert_success
  assert_output "OK"
}

# ===========================================================================
# 7. Budget weight accumulation is correct
#    (0.5 + 1.0 + 1.5 + 1.0 + 1.0 + 0.5 + 0.0 = 5.5)
# ===========================================================================

@test "recovery-burndown: full strategy weight sum = 5.5" {
  local total
  total=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" \
    "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN" "$W_GRACEFUL_STOP")
  [[ "$total" == "5.5" ]] || fail "Expected total weight 5.5, got $total"
}

@test "recovery-burndown: ceiling equals sum of all non-terminal weights" {
  # This is explicitly documented: ceiling = sum of non-zero weights
  local non_terminal_sum
  non_terminal_sum=$(compute_total_weight "$W_TRANSIENT" "$W_TOOL_DIAG" "$W_STATE_RECON" \
    "$W_AGENT_RESET" "$W_DEP_HEALTH" "$W_RESOURCE_CLEAN")
  [[ "$non_terminal_sum" == "$BUDGET_CEILING" ]] \
    || fail "Ceiling ($BUDGET_CEILING) should equal sum of non-terminal weights ($non_terminal_sum)"
}

@test "recovery-burndown: incremental budget accumulation tracks correctly" {
  # Simulate applying strategies one at a time and verify running total
  local forge_dir="${TEST_TEMP}/budget-accumulation/.forge"
  create_state_with_budget "$forge_dir" 0.0

  local strategies_and_weights=(
    "transient-retry:0.5"
    "tool-diagnosis:1.0"
    "state-reconstruction:1.5"
    "agent-reset:1.0"
    "dependency-health:1.0"
    "resource-cleanup:0.5"
  )

  local running_total="0.0"
  for entry in "${strategies_and_weights[@]}"; do
    local name="${entry%%:*}"
    local weight="${entry##*:}"
    running_total=$(_pf_add "$running_total" "$weight")

    FORGE_RUNNING_TOTAL="$running_total" FORGE_NAME="$name" FORGE_WEIGHT="$weight" \
      python3 - "$forge_dir/state.json" <<'PY'
import json
import os
import sys
from pathlib import Path

p = Path(sys.argv[1])
with p.open() as f:
    d = json.load(f)
d['recovery_budget']['total_weight'] = float(os.environ['FORGE_RUNNING_TOTAL'])
d['recovery_budget']['applications'].append({
    'strategy': os.environ['FORGE_NAME'],
    'weight': float(os.environ['FORGE_WEIGHT']),
    'stage': 'IMPLEMENTING',
    'timestamp': '2026-01-01T00:00:00Z',
})
with p.open('w') as f:
    json.dump(d, f, indent=2)
PY
  done

  # Verify final state
  run python3 - "$forge_dir/state.json" <<'PY'
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as f:
    d = json.load(f)
rb = d['recovery_budget']
assert rb['total_weight'] == 5.5, f"Expected 5.5, got {rb['total_weight']}"
assert len(rb['applications']) == 6, f"Expected 6 applications, got {len(rb['applications'])}"
# Verify sum of individual weights matches total
w_sum = sum(a['weight'] for a in rb['applications'])
assert w_sum == 5.5, f"Sum of application weights ({w_sum}) != total_weight (5.5)"
print('OK')
PY
  assert_success
  assert_output "OK"
}

@test "recovery-burndown: budget accumulation crosses warning thresholds correctly" {
  # Start at 0, apply strategies until we cross 80% and 90%
  local total="0.0"

  # transient-retry (0.5) -> total 0.5 (below 80%)
  total=$(_pf_add "$total" "$W_TRANSIENT")
  [[ $(_pf_cmp "$total" '<' "$WARNING_80PCT") -eq 1 ]] \
    || fail "After transient-retry ($total), should be below 80% ($WARNING_80PCT)"

  # tool-diagnosis (1.0) -> total 1.5 (below 80%)
  total=$(_pf_add "$total" "$W_TOOL_DIAG")
  [[ $(_pf_cmp "$total" '<' "$WARNING_80PCT") -eq 1 ]] \
    || fail "After tool-diagnosis ($total), should be below 80%"

  # state-reconstruction (1.5) -> total 3.0 (below 80%)
  total=$(_pf_add "$total" "$W_STATE_RECON")
  [[ $(_pf_cmp "$total" '<' "$WARNING_80PCT") -eq 1 ]] \
    || fail "After state-reconstruction ($total), should be below 80%"

  # agent-reset (1.0) -> total 4.0 (below 80%)
  total=$(_pf_add "$total" "$W_AGENT_RESET")
  [[ $(_pf_cmp "$total" '<' "$WARNING_80PCT") -eq 1 ]] \
    || fail "After agent-reset ($total), should be below 80%"

  # dependency-health (1.0) -> total 5.0 (above 80%, above 90%)
  total=$(_pf_add "$total" "$W_DEP_HEALTH")
  [[ $(_pf_cmp "$total" '>=' "$WARNING_80PCT") -eq 1 ]] \
    || fail "After dependency-health ($total), should be above 80% ($WARNING_80PCT)"
  [[ $(_pf_cmp "$total" '>=' "$WARNING_90PCT") -eq 1 ]] \
    || fail "After dependency-health ($total), should be above 90% ($WARNING_90PCT)"

  # resource-cleanup (0.5) -> total 5.5 (at ceiling)
  total=$(_pf_add "$total" "$W_RESOURCE_CLEAN")
  [[ $(_pf_cmp "$total" '>=' "$BUDGET_CEILING") -eq 1 ]] \
    || fail "After resource-cleanup ($total), should be at ceiling ($BUDGET_CEILING)"
}
