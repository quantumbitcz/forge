#!/usr/bin/env bats
# Contract tests: shared/convergence-engine.md — validates the convergence engine document.

load '../helpers/test-helpers'

ENGINE="$PLUGIN_ROOT/shared/convergence-engine.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "convergence-engine: document exists" {
  [[ -f "$ENGINE" ]]
}

# ---------------------------------------------------------------------------
# 2. Three convergence states documented: IMPROVING, PLATEAUED, REGRESSING
# ---------------------------------------------------------------------------
@test "convergence-engine: three convergence states documented" {
  grep -q "IMPROVING" "$ENGINE" || fail "IMPROVING state not documented"
  grep -q "PLATEAUED" "$ENGINE" || fail "PLATEAUED state not documented"
  grep -q "REGRESSING" "$ENGINE" || fail "REGRESSING state not documented"
}

# ---------------------------------------------------------------------------
# 3. Two-phase model documented: correctness, perfection, safety_gate
# ---------------------------------------------------------------------------
@test "convergence-engine: two-phase model with safety gate documented" {
  grep -q "correctness" "$ENGINE" \
    || fail "Phase 1 (Correctness) not documented"
  grep -q "perfection" "$ENGINE" \
    || fail "Phase 2 (Perfection) not documented"
  grep -qi "safety.gate\|safety_gate" "$ENGINE" \
    || fail "Safety gate not documented"
}

# ---------------------------------------------------------------------------
# 4. Algorithm documented with decide_next function
# ---------------------------------------------------------------------------
@test "convergence-engine: algorithm documented with decide_next" {
  grep -q "decide_next" "$ENGINE" || fail "decide_next function not documented"
}

# ---------------------------------------------------------------------------
# 5. Configuration section with all 5 parameters
# ---------------------------------------------------------------------------
@test "convergence-engine: configuration documents all 5 parameters" {
  local params=(max_iterations plateau_threshold plateau_patience target_score safety_gate)
  for param in "${params[@]}"; do
    grep -q "$param" "$ENGINE" \
      || fail "Configuration parameter $param not documented"
  done
}

# ---------------------------------------------------------------------------
# 6. PREFLIGHT constraints documented with ranges
# ---------------------------------------------------------------------------
@test "convergence-engine: PREFLIGHT constraints with valid ranges" {
  grep -q "3.*20\|>= 3.*<= 20" "$ENGINE" \
    || fail "max_iterations range 3-20 not documented"
  grep -q "0.*10\|>= 0.*<= 10" "$ENGINE" \
    || fail "plateau_threshold range 0-10 not documented"
  grep -q "1.*5\|>= 1.*<= 5" "$ENGINE" \
    || fail "plateau_patience range 1-5 not documented"
}

# ---------------------------------------------------------------------------
# 7. State schema section references convergence object
# ---------------------------------------------------------------------------
@test "convergence-engine: state schema section documents convergence object" {
  grep -qi "state.json\|state_schema\|state schema" "$ENGINE" \
    || fail "State schema reference not documented"
  grep -q "convergence" "$ENGINE" \
    || fail "convergence object not documented"
}

# ---------------------------------------------------------------------------
# 8. Interaction with existing config documented
# ---------------------------------------------------------------------------
@test "convergence-engine: interaction with max_review_cycles and max_test_cycles documented" {
  grep -q "max_review_cycles" "$ENGINE" \
    || fail "Interaction with max_review_cycles not documented"
  grep -q "max_test_cycles" "$ENGINE" \
    || fail "Interaction with max_test_cycles not documented"
}

# ---------------------------------------------------------------------------
# 9. Phase 2 skips VERIFY explicitly stated
# ---------------------------------------------------------------------------
@test "convergence-engine: Phase 2 skips VERIFY documented" {
  grep -qi "phase 2 skips verify\|skips verify.*iteration\|only review scores" "$ENGINE" \
    || fail "Phase 2 skipping VERIFY not documented"
}

# ---------------------------------------------------------------------------
# 10. Safety gate failure routes back to correctness
# ---------------------------------------------------------------------------
@test "convergence-engine: safety gate failure transitions to correctness" {
  grep -qi "safety.*gate.*fail.*correctness\|back to.*correctness\|transition.*back.*correctness\|routes to Phase 1" "$ENGINE" \
    || fail "Safety gate failure -> correctness transition not documented"
}

# ---------------------------------------------------------------------------
# 11. Safety gate failures counter for cross-phase oscillation prevention
# ---------------------------------------------------------------------------
@test "convergence-engine: safety gate failures counter documents escalation at >= 2" {
  grep -q "safety_gate_failures" "$ENGINE" \
    || fail "safety_gate_failures counter not documented"
  grep -qi "oscillation\|>= 2\|ESCALATE" "$ENGINE" \
    || fail "Cross-phase oscillation escalation not documented"
}

# ---------------------------------------------------------------------------
# 12. analysis_pass definition documented
# ---------------------------------------------------------------------------
@test "convergence-engine: analysis_pass definition documented" {
  grep -q "analysis_pass" "$ENGINE" \
    || fail "analysis_pass definition not documented"
}
