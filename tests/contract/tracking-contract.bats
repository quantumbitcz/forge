#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator-core.md"
  ORCHESTRATOR_ALL=("$PLUGIN_ROOT/agents/fg-100-orchestrator-core.md" "$PLUGIN_ROOT/agents/fg-100-orchestrator-boot.md" "$PLUGIN_ROOT/agents/fg-100-orchestrator-execute.md" "$PLUGIN_ROOT/agents/fg-100-orchestrator-ship.md")
  STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
}

@test "tracking-contract: orchestrator references tracking-ops.sh" {
  grep -q "tracking-ops.sh" "${ORCHESTRATOR_ALL[@]}"
}

@test "tracking-contract: orchestrator creates worktree at PREFLIGHT" {
  grep -q "Create Worktree" "${ORCHESTRATOR_ALL[@]}"
  # The worktree section should be in the boot file (PREFLIGHT phase)
  grep -q "Create Worktree" "$PLUGIN_ROOT/agents/fg-100-orchestrator-boot.md"
}

@test "tracking-contract: orchestrator has sub-agent dispatch pattern" {
  grep -q "Sub-Agent Dispatch Pattern" "${ORCHESTRATOR_ALL[@]}"
}

@test "tracking-contract: orchestrator wraps Agent dispatch with TaskCreate" {
  # Orchestrator uses [dispatch] shorthand per Dispatch Protocol section, or explicit TaskCreate
  grep -q "\[dispatch\]\|\[dispatch fg-\|TaskCreate.*Dispatching\|Dispatch Protocol" "${ORCHESTRATOR_ALL[@]}"
}

@test "tracking-contract: orchestrator has kanban transitions table" {
  grep -q "Kanban Status Transitions" "${ORCHESTRATOR_ALL[@]}"
}

@test "tracking-contract: orchestrator stores ticket_id in state.json" {
  grep -q "ticket_id" "${ORCHESTRATOR_ALL[@]}"
}

@test "tracking-contract: orchestrator stores branch_name in state.json" {
  grep -q "branch_name" "${ORCHESTRATOR_ALL[@]}"
}

@test "tracking-contract: stage-contract has worktree at PREFLIGHT" {
  grep -q "worktree.*PREFLIGHT\|Worktree.*Stage 0\|PREFLIGHT.*worktree" "$STAGE_CONTRACT" || \
  grep -q "Worktree Isolation" "$STAGE_CONTRACT"
}

@test "tracking-contract: stage-contract has cross-cutting constraints" {
  grep -q "Cross-Cutting Constraints" "$STAGE_CONTRACT"
}

@test "tracking-contract: stage-contract documents kanban graceful degradation" {
  grep -q "graceful degradation\|silently skipped" "$STAGE_CONTRACT"
}

@test "tracking-contract: orchestrator enforces convention stack soft cap" {
  grep -q "12 files\|Stack.*12\|soft cap" "${ORCHESTRATOR_ALL[@]}" \
    || fail "Convention stack soft cap (12 files) not documented in orchestrator"
}

@test "tracking-contract: orchestrator stores shallow_clone in state.json" {
  grep -q "shallow_clone" "${ORCHESTRATOR_ALL[@]}"
}
