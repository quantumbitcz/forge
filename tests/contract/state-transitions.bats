#!/usr/bin/env bats
# Contract tests: shared/state-transitions.md — validates the formal state
# machine transition table that governs all orchestrator control flow decisions.

load '../helpers/test-helpers'

TRANSITIONS="$PLUGIN_ROOT/shared/state-transitions.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
CONVERGENCE="$PLUGIN_ROOT/shared/convergence-engine.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "state-transitions: document exists" {
  [[ -f "$TRANSITIONS" ]]
}

# ---------------------------------------------------------------------------
# 2. All 10 pipeline states present in the transition table
# ---------------------------------------------------------------------------
@test "state-transitions: all 10 pipeline states present" {
  for state in PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING; do
    grep -q "$state" "$TRANSITIONS" \
      || fail "Pipeline state '$state' not found in transition table"
  done
}

# ---------------------------------------------------------------------------
# 3. Convergence phases documented (correctness, perfection, safety_gate)
# ---------------------------------------------------------------------------
@test "state-transitions: convergence phases documented" {
  grep -q "correctness" "$TRANSITIONS" \
    || fail "Convergence phase 'correctness' not documented"
  grep -q "perfection" "$TRANSITIONS" \
    || fail "Convergence phase 'perfection' not documented"
  grep -qi "safety_gate\|safety.gate" "$TRANSITIONS" \
    || fail "Convergence phase 'safety_gate' not documented"
}

# ---------------------------------------------------------------------------
# 4. Table columns: current_state, event, guard, next_state, action
# ---------------------------------------------------------------------------
@test "state-transitions: table has required columns" {
  grep -qi "current_state\|current state" "$TRANSITIONS" \
    || fail "Column 'current_state' not found"
  grep -qi "event" "$TRANSITIONS" \
    || fail "Column 'event' not found"
  grep -qi "guard" "$TRANSITIONS" \
    || fail "Column 'guard' not found"
  grep -qi "next_state\|next state" "$TRANSITIONS" \
    || fail "Column 'next_state' not found"
  grep -qi "action" "$TRANSITIONS" \
    || fail "Column 'action' not found"
}

# ---------------------------------------------------------------------------
# 5. Deterministic guarantee stated
# ---------------------------------------------------------------------------
@test "state-transitions: deterministic guarantee documented" {
  grep -qi "deterministic" "$TRANSITIONS" \
    || fail "Deterministic guarantee not stated in document"
}

# ---------------------------------------------------------------------------
# 6. Error transitions from ANY state documented
# ---------------------------------------------------------------------------
@test "state-transitions: error transitions from ANY state documented" {
  grep -qi "budget_exhausted" "$TRANSITIONS" \
    || fail "budget_exhausted error transition not documented"
  grep -qi "unrecoverable_error\|unrecoverable" "$TRANSITIONS" \
    || fail "unrecoverable_error transition not documented"
  grep -qi "user_abort" "$TRANSITIONS" \
    || fail "user_abort transition not documented"
  grep -qi "ANY\|any state\|any pipeline state" "$TRANSITIONS" \
    || fail "ANY-state error transition section not documented"
}

# ---------------------------------------------------------------------------
# 7. Orchestrator references state-transitions.md
# ---------------------------------------------------------------------------
@test "state-transitions: orchestrator references state-transitions.md" {
  grep -q "state-transitions.md" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference state-transitions.md"
}

# ---------------------------------------------------------------------------
# 8. Convergence engine references state-transitions.md
# ---------------------------------------------------------------------------
@test "state-transitions: convergence engine references state-transitions.md" {
  grep -q "state-transitions.md" "$CONVERGENCE" \
    || fail "Convergence engine does not reference state-transitions.md"
}

# ---------------------------------------------------------------------------
# 9. Guard conditions present in transition rows
# ---------------------------------------------------------------------------
@test "state-transitions: guard conditions present in transitions" {
  # At least these key guards must appear
  grep -qi "dry_run" "$TRANSITIONS" \
    || fail "Guard 'dry_run' not found in transition table"
  grep -qi "verdict.*GO\|verdict_GO\|verdict == GO\|verdict: GO" "$TRANSITIONS" \
    || fail "Guard for GO verdict not found"
  grep -qi "verdict.*REVISE\|verdict_REVISE\|verdict == REVISE\|verdict: REVISE" "$TRANSITIONS" \
    || fail "Guard for REVISE verdict not found"
  grep -qi "tests_pass\|tests pass" "$TRANSITIONS" \
    || fail "Guard 'tests_pass' not found"
  grep -qi "score.*target\|target_score\|score >= target" "$TRANSITIONS" \
    || fail "Guard for target score not found"
}

# ---------------------------------------------------------------------------
# 10. Budget transitions documented (recovery budget and total_retries)
# ---------------------------------------------------------------------------
@test "state-transitions: budget transitions documented" {
  grep -qi "recovery_budget\|recovery budget" "$TRANSITIONS" \
    || fail "Recovery budget transitions not documented"
  grep -qi "total_retries" "$TRANSITIONS" \
    || fail "total_retries budget enforcement not documented"
  grep -qi "budget" "$TRANSITIONS" \
    || fail "Budget concept not documented in transitions"
}
