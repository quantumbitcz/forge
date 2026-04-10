#!/usr/bin/env bats
# Contract tests: required decision point catalog

load '../helpers/test-helpers'

DECISION_LOG="$PLUGIN_ROOT/shared/decision-log.md"

# ---------------------------------------------------------------------------
# 1. All 12 decision types documented
# ---------------------------------------------------------------------------
@test "decision-catalog: all 12 required decision types documented" {
  local count=0
  for dtype in intent_classification scope_assessment plan_approach \
               validation_verdict convergence_evaluation convergence_phase_transition \
               recovery_classification finding_severity dedup_merge \
               evidence_verdict user_escalation auto_tune; do
    if grep -q "\`$dtype\`" "$DECISION_LOG"; then
      count=$((count + 1))
    else
      fail "Required decision type '$dtype' not found in decision-log.md"
    fi
  done
  [[ $count -eq 12 ]] \
    || fail "Expected 12 required decision types, found $count"
}

# ---------------------------------------------------------------------------
# 2. Table has Agent, When, Logged Fields columns
# ---------------------------------------------------------------------------
@test "decision-catalog: table has Agent, When, Logged Fields columns" {
  grep -q "| Agent |" "$DECISION_LOG" \
    || fail "Table missing 'Agent' column"
  grep -q "| When |" "$DECISION_LOG" \
    || fail "Table missing 'When' column"
  grep -q "| Logged Fields |" "$DECISION_LOG" \
    || fail "Table missing 'Logged Fields' column"
}

# ---------------------------------------------------------------------------
# 3. QUAL-DECISION-GAP documented
# ---------------------------------------------------------------------------
@test "decision-catalog: QUAL-DECISION-GAP finding documented" {
  grep -q "QUAL-DECISION-GAP" "$DECISION_LOG" \
    || fail "QUAL-DECISION-GAP finding not documented"
}

# ---------------------------------------------------------------------------
# 4. fg-700 referenced for gap detection
# ---------------------------------------------------------------------------
@test "decision-catalog: fg-700-retrospective referenced for gap detection" {
  grep -q "fg-700-retrospective" "$DECISION_LOG" \
    || fail "fg-700-retrospective not referenced for gap detection"
}

# ---------------------------------------------------------------------------
# 5. "Required Decision Points" section exists
# ---------------------------------------------------------------------------
@test "decision-catalog: 'Required Decision Points' section exists" {
  grep -q "## Required Decision Points" "$DECISION_LOG" \
    || fail "'Required Decision Points' section not found"
}

# ---------------------------------------------------------------------------
# 6. intent_classification assigned to Orchestrator
# ---------------------------------------------------------------------------
@test "decision-catalog: intent_classification assigned to Orchestrator" {
  grep -A1 "intent_classification" "$DECISION_LOG" | grep -qi "orchestrator" \
    || fail "intent_classification not assigned to Orchestrator"
}

# ---------------------------------------------------------------------------
# 7. evidence_verdict assigned to fg-590
# ---------------------------------------------------------------------------
@test "decision-catalog: evidence_verdict assigned to fg-590" {
  grep "evidence_verdict" "$DECISION_LOG" | grep -q "fg-590" \
    || fail "evidence_verdict not assigned to fg-590"
}

# ---------------------------------------------------------------------------
# 8. auto_tune assigned to Retrospective/fg-700
# ---------------------------------------------------------------------------
@test "decision-catalog: auto_tune assigned to Retrospective (fg-700)" {
  grep "auto_tune" "$DECISION_LOG" | grep -qi "retrospective\|fg-700" \
    || fail "auto_tune not assigned to Retrospective/fg-700"
}

# ---------------------------------------------------------------------------
# 9. Gap Detection subsection exists
# ---------------------------------------------------------------------------
@test "decision-catalog: Gap Detection subsection exists" {
  grep -q "### Gap Detection" "$DECISION_LOG" \
    || fail "'Gap Detection' subsection not found"
}
