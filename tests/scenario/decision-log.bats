#!/usr/bin/env bats
# Scenario tests: decision log integration across pipeline components

# Covers:

load '../helpers/test-helpers'

DECISION_LOG="$PLUGIN_ROOT/shared/decision-log.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
CONVERGENCE="$PLUGIN_ROOT/shared/convergence-engine.md"

# ---------------------------------------------------------------------------
# 1. All 10 decision types are documented with descriptions
# ---------------------------------------------------------------------------
@test "decision-log-scenario: all 10 decision types have descriptions in the type table" {
  local types_section
  types_section=$(sed -n '/## Decision Types/,/^## /p' "$DECISION_LOG")
  for dtype in state_transition convergence_phase_transition convergence_evaluation \
               recovery_attempt circuit_breaker_state_change escalation \
               mode_classification domain_detection reviewer_conflict evidence_verdict; do
    echo "$types_section" | grep -q "$dtype" \
      || fail "Decision type '$dtype' missing from Decision Types table"
  done
}

# ---------------------------------------------------------------------------
# 2. Orchestrator emits decision log entries
# ---------------------------------------------------------------------------
@test "decision-log-scenario: orchestrator documents decision log emission" {
  grep -qE "decision log|decisions\.jsonl|decision-log\.md" "$ORCHESTRATOR" \
    || fail "Orchestrator does not document decision log emission"
  # Should mention specific decision types the orchestrator emits
  grep -qE "state.transition|convergence|recovery|escalation" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference key decision types it emits"
}

# ---------------------------------------------------------------------------
# 3. Convergence engine emits decision log entries
# ---------------------------------------------------------------------------
@test "decision-log-scenario: convergence engine documents decision log emission" {
  grep -qE "decision.*log|decisions\.jsonl|decision-log\.md" "$CONVERGENCE" \
    || fail "Convergence engine does not document decision log emission"
  grep -qE "convergence_evaluation|convergence_phase_transition" "$CONVERGENCE" \
    || fail "Convergence engine does not reference its decision types"
}

# ---------------------------------------------------------------------------
# 4. File location is .forge/decisions.jsonl
# ---------------------------------------------------------------------------
@test "decision-log-scenario: file location consistent across documents" {
  grep -q "\.forge/decisions\.jsonl" "$DECISION_LOG" \
    || fail "decision-log.md does not reference .forge/decisions.jsonl"
  grep -q "decisions\.jsonl" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference decisions.jsonl"
}

# ---------------------------------------------------------------------------
# 5. Archival documented for size management
# ---------------------------------------------------------------------------
@test "decision-log-scenario: archival and size management documented" {
  grep -qi "1000" "$DECISION_LOG" \
    || fail "Line threshold (1000) for archival not documented"
  grep -qi "archive\|\.gz\|compress" "$DECISION_LOG" \
    || fail "Archival mechanism not documented"
}
