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

# ---------------------------------------------------------------------------
# 13. max_iterations guard in perfection phase
# ---------------------------------------------------------------------------
@test "convergence-engine: perfection phase has max_iterations guard" {
  grep -q "total_iterations >= max_iterations" "$ENGINE" \
    || fail "max_iterations guard not documented in perfection phase"
}

# ---------------------------------------------------------------------------
# 14. First-cycle plateau prevention (phase_iterations > 0)
# ---------------------------------------------------------------------------
@test "convergence-engine: first-cycle plateau prevention documented" {
  grep -q "phase_iterations > 0" "$ENGINE" \
    || fail "First-cycle plateau prevention (phase_iterations > 0) not documented"
}

# ---------------------------------------------------------------------------
# 15. plateau_count reset on safety gate restart
# ---------------------------------------------------------------------------
@test "convergence-engine: plateau_count reset on safety gate failure" {
  grep -qi "reset plateau_count" "$ENGINE" \
    || fail "plateau_count reset on safety gate -> correctness transition not documented"
}

# ---------------------------------------------------------------------------
# 16. PHASE_A_FAILURE handling path documented
# ---------------------------------------------------------------------------
@test "convergence-engine: PHASE_A_FAILURE handling documented" {
  grep -q "PHASE_A_FAILURE" "$ENGINE" \
    || fail "PHASE_A_FAILURE handling path not documented"
}

# ---------------------------------------------------------------------------
# 17. Phase A inner cap (verify_fix_count >= max_fix_loops) documented
# ---------------------------------------------------------------------------
@test "convergence-engine: Phase A inner cap verify_fix_count >= max_fix_loops documented" {
  grep -q "verify_fix_count >= max_fix_loops" "$ENGINE" \
    || fail "Phase A inner cap (verify_fix_count >= max_fix_loops) not documented in algorithm"
}

# ---------------------------------------------------------------------------
# 18. Global budget interaction documented (total_iterations -> total_retries)
# ---------------------------------------------------------------------------
@test "convergence-engine: global budget interaction documented" {
  grep -q "total_retries" "$ENGINE" \
    || fail "Global budget interaction (total_retries) not documented"
  grep -q "total_retries_max" "$ENGINE" \
    || fail "total_retries_max reference not documented"
}

# ---------------------------------------------------------------------------
# 19. Consecutive Dip Rule interaction documented
# ---------------------------------------------------------------------------
@test "convergence-engine: Consecutive Dip Rule interaction documented" {
  grep -qi "Consecutive Dip Rule\|dip rule" "$ENGINE" \
    || fail "Consecutive Dip Rule interaction not documented"
}

# ---------------------------------------------------------------------------
# 20. Score escalation ladder documented
# ---------------------------------------------------------------------------
@test "convergence-engine: score escalation ladder with all 3 bands documented" {
  grep -q "pass_threshold" "$ENGINE" \
    || fail "pass_threshold band not documented in escalation ladder"
  grep -q "concerns_threshold" "$ENGINE" \
    || fail "concerns_threshold band not documented in escalation ladder"
  grep -qi "PASS.*CONCERNS.*FAIL\|PASS verdict\|CONCERNS verdict\|FAIL verdict" "$ENGINE" \
    || fail "PASS/CONCERNS/FAIL verdicts not documented in escalation ladder"
}

# ---------------------------------------------------------------------------
# 21. Retrospective auto-tuning rules documented
# ---------------------------------------------------------------------------
@test "convergence-engine: retrospective auto-tuning documented" {
  grep -qi "auto-tuning\|Auto-Tuning\|retrospective.*adjust" "$ENGINE" \
    || fail "Retrospective auto-tuning not documented"
  grep -q "pl-700-retrospective" "$ENGINE" \
    || fail "pl-700-retrospective not referenced in auto-tuning section"
}

# ---------------------------------------------------------------------------
# 22. Safety gate restart resets last_score_delta and convergence_state
# ---------------------------------------------------------------------------
@test "convergence-engine: safety gate restart resets last_score_delta" {
  grep -q "reset last_score_delta" "$ENGINE" \
    || fail "Safety gate restart does not specify last_score_delta reset"
}

@test "convergence-engine: safety gate restart resets convergence_state to IMPROVING" {
  grep -q 'reset convergence_state to "IMPROVING"' "$ENGINE" \
    || fail "Safety gate restart does not specify convergence_state reset"
}

# ---------------------------------------------------------------------------
# 23. PLATEAUED transition specifies score-based routing
# ---------------------------------------------------------------------------
@test "convergence-engine: PLATEAUED transition routes by score band" {
  grep -q "pass_threshold.*safety_gate\|transition directly to.*safety_gate" "$ENGINE" \
    || fail "PLATEAUED transition does not specify score >= pass_threshold routing"
  grep -qi "concerns.*ESCALATE\|ESCALATE.*user" "$ENGINE" \
    || fail "PLATEAUED transition does not specify CONCERNS escalation"
}

# ---------------------------------------------------------------------------
# 24. Phase_history trimming documented
# ---------------------------------------------------------------------------
@test "convergence-engine: phase_history capped at 50 entries" {
  grep -q "50 entries\|Capped at 50" "$ENGINE" \
    || fail "phase_history 50-entry cap not documented"
}

# ---------------------------------------------------------------------------
# 25. Oscillation vs escalation precedence documented
# ---------------------------------------------------------------------------
@test "convergence-engine: REGRESSING takes precedence over PLATEAUED" {
  grep -qi "REGRESSING takes priority\|REGRESSING.*checked first\|precedence" "$ENGINE" \
    || fail "Oscillation vs escalation precedence not documented"
}
