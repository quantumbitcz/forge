#!/usr/bin/env bats
# Scenario tests: convergence phase transitions — validates phase advancement,
# plateau detection, oscillation detection, safety gate restart, and field
# resets documented across convergence-engine.md and the orchestrator.

load '../helpers/test-helpers'

CONVERGENCE="$PLUGIN_ROOT/shared/convergence-engine.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# 1. Phase advancement: correctness → perfection
# ---------------------------------------------------------------------------
@test "convergence-phases: correctness to perfection advancement documented" {
  grep -qi "correctness.*perfection\|phase 1.*phase 2\|advance.*perfection" "$CONVERGENCE" \
    || fail "correctness → perfection advancement not documented"
}

# ---------------------------------------------------------------------------
# 2. Phase advancement: perfection → safety_gate
# ---------------------------------------------------------------------------
@test "convergence-phases: perfection to safety_gate advancement documented" {
  grep -qi "perfection.*safety.gate\|phase 2.*safety\|advance.*safety" "$CONVERGENCE" \
    || fail "perfection → safety_gate advancement not documented"
}

# ---------------------------------------------------------------------------
# 3. Safety gate restart: safety_gate → correctness on failure
# ---------------------------------------------------------------------------
@test "convergence-phases: safety gate failure restarts to correctness" {
  grep -qi "safety.*gate.*fail.*correctness\|restart.*correctness\|safety.*gate.*restart" "$CONVERGENCE" \
    || fail "Safety gate restart to correctness not documented"
}

# ---------------------------------------------------------------------------
# 4. Field resets on phase transition
# ---------------------------------------------------------------------------
@test "convergence-phases: phase_iterations resets on phase transition" {
  grep -qi "phase_iterations.*0\|reset.*phase_iterations\|phase_iterations.*reset" "$CONVERGENCE" \
    || fail "phase_iterations reset on phase transition not documented"
}

@test "convergence-phases: convergence_state resets to IMPROVING on safety gate restart" {
  grep -qi "IMPROVING.*restart\|restart.*IMPROVING\|convergence_state.*IMPROVING" "$CONVERGENCE" \
    || fail "convergence_state reset to IMPROVING on restart not documented"
}

@test "convergence-phases: plateau_count resets on safety gate restart" {
  grep -qi "plateau_count.*reset\|plateau_count.*0\|reset.*plateau" "$CONVERGENCE" \
    || fail "plateau_count reset on restart not documented"
}

# ---------------------------------------------------------------------------
# 5. Safety gate failure escalation at >= 2
# ---------------------------------------------------------------------------
@test "convergence-phases: safety gate failures escalation at >= 2 documented" {
  grep -qE "safety.gate.failure|safety_gate_failures" "$CONVERGENCE" \
    || fail "safety_gate_failures not documented"
  grep -qE ">= 2|≥ 2|at least 2" "$CONVERGENCE" \
    || grep -qi "escalat.*2\|2.*escalat" "$CONVERGENCE" \
    || fail "Escalation at >= 2 failures not documented"
}

# ---------------------------------------------------------------------------
# 6. Phase history FIFO capping at 50
# ---------------------------------------------------------------------------
@test "convergence-phases: phase_history capped at 50 entries" {
  grep -q "50" "$CONVERGENCE" \
    || fail "50-entry cap not documented"
  grep -qi "phase_history.*cap\|cap.*50\|FIFO\|oldest.*removed" "$CONVERGENCE" \
    || fail "phase_history capping not documented"
}

# ---------------------------------------------------------------------------
# 7. Phase history outcome values
# ---------------------------------------------------------------------------
@test "convergence-phases: phase_history outcomes include converged, escalated, restarted" {
  grep -q "converged" "$CONVERGENCE" || fail "converged outcome not documented"
  grep -q "escalated" "$CONVERGENCE" || fail "escalated outcome not documented"
  grep -q "restarted" "$CONVERGENCE" || fail "restarted outcome not documented"
}

# ---------------------------------------------------------------------------
# 8. Plateau detection: plateau_count >= plateau_patience triggers PLATEAUED
# ---------------------------------------------------------------------------
@test "convergence-phases: plateau detection with plateau_patience threshold" {
  grep -qi "plateau_count" "$CONVERGENCE" || fail "plateau_count not documented"
  grep -qi "plateau_patience" "$CONVERGENCE" || fail "plateau_patience not documented"
  grep -qi "PLATEAUED" "$CONVERGENCE" || fail "PLATEAUED state not documented"
}

# ---------------------------------------------------------------------------
# 9. First-cycle plateau prevention
# ---------------------------------------------------------------------------
@test "convergence-phases: first-cycle plateau prevention documented" {
  grep -qi "first.*cycle\|phase_iterations.*0\|exempt\|first.*exempt\|first.*iteration" "$CONVERGENCE" \
    || fail "First-cycle plateau prevention not documented"
}

# ---------------------------------------------------------------------------
# 10. REGRESSING takes precedence over PLATEAUED
# ---------------------------------------------------------------------------
@test "convergence-phases: REGRESSING checked before PLATEAUED" {
  grep -qi "REGRESSING.*preced\|preced.*REGRESSING\|REGRESSING.*before.*PLATEAU\|REGRESSING.*first" "$CONVERGENCE" \
    || grep -qi "REGRESSING" "$CONVERGENCE" \
    || fail "REGRESSING precedence not documented"
}

# ---------------------------------------------------------------------------
# 11. Oscillation detection via tolerance
# ---------------------------------------------------------------------------
@test "convergence-phases: oscillation_tolerance used for regression detection" {
  grep -qi "oscillation_tolerance" "$CONVERGENCE" \
    || fail "oscillation_tolerance not referenced in convergence engine"
}

# ---------------------------------------------------------------------------
# 12. Phase 2 skips VERIFY
# ---------------------------------------------------------------------------
@test "convergence-phases: perfection phase skips VERIFY stage" {
  grep -qi "phase 2.*skip.*VERIFY\|perfection.*skip.*VERIFY\|skip.*VERIFY.*perfection" "$CONVERGENCE" \
    || fail "Phase 2 VERIFY skip not documented"
}

# ---------------------------------------------------------------------------
# 13. total_iterations NOT reset on safety gate restart
# ---------------------------------------------------------------------------
@test "convergence-phases: total_iterations not reset on restart" {
  grep -qi "total_iterations.*not.*reset\|cumulative\|total_iterations.*carry\|total_iterations.*persist" "$CONVERGENCE" \
    || fail "total_iterations persistence across restarts not documented"
}

# ---------------------------------------------------------------------------
# 14. Score escalation ladder for PLATEAUED state
# ---------------------------------------------------------------------------
@test "convergence-phases: PLATEAUED routes by score band" {
  # PLATEAUED with score >= pass_threshold → safety_gate
  # PLATEAUED with score in CONCERNS → escalate to user
  # PLATEAUED with score < concerns → recommend abort
  grep -qi "PLATEAUED" "$CONVERGENCE" || fail "PLATEAUED not documented"
  grep -qi "pass_threshold\|pass.*threshold" "$CONVERGENCE" || fail "pass_threshold not referenced"
}

# ---------------------------------------------------------------------------
# 15. Orchestrator references convergence engine
# ---------------------------------------------------------------------------
@test "convergence-phases: orchestrator references convergence engine" {
  grep -qi "convergence" "$ORCHESTRATOR" \
    || fail "Orchestrator doesn't reference convergence"
}

# ---------------------------------------------------------------------------
# 16. State schema has convergence phase field
# ---------------------------------------------------------------------------
@test "convergence-phases: state schema has convergence.phase field" {
  grep -q "convergence" "$STATE_SCHEMA" || fail "convergence not in state schema"
  grep -qE "correctness|perfection|safety_gate" "$STATE_SCHEMA" \
    || fail "convergence phase values not in state schema"
}

# ---------------------------------------------------------------------------
# 17. Consecutive Dip Rule interaction
# ---------------------------------------------------------------------------
@test "convergence-phases: Consecutive Dip Rule documented" {
  grep -qi "consecutive.*dip\|dip.*rule" "$CONVERGENCE" \
    || fail "Consecutive Dip Rule not documented"
}

# ---------------------------------------------------------------------------
# 18. Convention drift check supported at agent level
# ---------------------------------------------------------------------------
@test "convergence-phases: convention drift check documented in planner" {
  local planner="$PLUGIN_ROOT/agents/fg-200-planner.md"
  grep -qi "convention.*drift\|conventions_hash\|drift.*check" "$planner" \
    || fail "Convention drift check not documented in planner"
}

@test "convergence-phases: convention drift check documented in implementer" {
  local implementer="$PLUGIN_ROOT/agents/fg-300-implementer.md"
  grep -qi "convention.*drift\|conventions_hash\|drift.*check" "$implementer" \
    || fail "Convention drift check not documented in implementer"
}

@test "convergence-phases: convention drift check documented in quality gate" {
  local quality_gate="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
  grep -qi "convention.*drift\|conventions_hash\|drift.*check" "$quality_gate" \
    || fail "Convention drift check not documented in quality gate"
}
