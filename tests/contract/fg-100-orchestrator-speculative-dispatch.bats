#!/usr/bin/env bats

ORCH="$BATS_TEST_DIRNAME/../../agents/fg-100-orchestrator.md"

@test "orchestrator has Speculative Dispatch (PLAN) subsection" {
  grep -q "^### Speculative Dispatch (PLAN)" "$ORCH"
}

@test "orchestrator references shared/speculation.md" {
  grep -q "shared/speculation.md" "$ORCH"
}

@test "orchestrator documents ambiguity detection shell-out" {
  grep -q "python3 hooks/_py/speculation.py detect-ambiguity" "$ORCH"
}

@test "orchestrator documents N parallel planner dispatch" {
  grep -q "Dispatch N .fg-200-planner. instances in parallel" "$ORCH"
}

@test "orchestrator documents parallel validator dispatch" {
  grep -q "N parallel .fg-210-validator." "$ORCH"
}

@test "orchestrator persists candidates via persist-candidate shell-out" {
  grep -q "python3 hooks/_py/speculation.py persist-candidate" "$ORCH"
}

@test "orchestrator documents diversity degraded fallback" {
  grep -q "speculation.degraded" "$ORCH"
  grep -q "low_diversity" "$ORCH"
}

@test "orchestrator documents cost ceiling abort path" {
  grep -q "estimate-cost" "$ORCH"
  grep -q "token_ceiling_multiplier" "$ORCH"
}
