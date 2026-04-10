#!/usr/bin/env bats
# Contract tests: decision log for observability

load '../helpers/test-helpers'

DECISION_LOG="$PLUGIN_ROOT/shared/decision-log.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
CONVERGENCE="$PLUGIN_ROOT/shared/convergence-engine.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "decision-log-contract: shared/decision-log.md exists" {
  [[ -f "$DECISION_LOG" ]] \
    || fail "shared/decision-log.md does not exist"
}

# ---------------------------------------------------------------------------
# 2. Schema defined with required fields
# ---------------------------------------------------------------------------
@test "decision-log-contract: schema defines required fields (ts, agent, decision, input, choice, alternatives, reason)" {
  for field in ts agent decision input choice alternatives reason; do
    grep -q "$field" "$DECISION_LOG" \
      || fail "Required field '$field' not found in decision-log.md"
  done
}

# ---------------------------------------------------------------------------
# 3. File location documented (decisions.jsonl in .forge/)
# ---------------------------------------------------------------------------
@test "decision-log-contract: file location is .forge/decisions.jsonl" {
  grep -q "\.forge/decisions\.jsonl" "$DECISION_LOG" \
    || fail ".forge/decisions.jsonl location not documented"
}

# ---------------------------------------------------------------------------
# 4. Orchestrator references decision-log.md or decisions.jsonl
# ---------------------------------------------------------------------------
@test "decision-log-contract: orchestrator references decision logging" {
  grep -qE "decision-log\.md|decisions\.jsonl" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference decision-log.md or decisions.jsonl"
}

# ---------------------------------------------------------------------------
# 5. Convergence engine references decision logging
# ---------------------------------------------------------------------------
@test "decision-log-contract: convergence engine references decision logging" {
  grep -qE "decision.*log|decisions\.jsonl|decision-log\.md" "$CONVERGENCE" \
    || fail "Convergence engine does not reference decision logging"
}

# ---------------------------------------------------------------------------
# 6. Key decision points enumerated (all 10 types)
# ---------------------------------------------------------------------------
@test "decision-log-contract: all 10 decision types documented" {
  local count=0
  for dtype in state_transition convergence_phase_transition convergence_evaluation \
               recovery_attempt circuit_breaker_state_change escalation \
               mode_classification domain_detection reviewer_conflict evidence_verdict; do
    if grep -q "$dtype" "$DECISION_LOG"; then
      count=$((count + 1))
    else
      fail "Decision type '$dtype' not found in decision-log.md"
    fi
  done
  [[ $count -eq 10 ]] \
    || fail "Expected 10 decision types, found $count"
}
