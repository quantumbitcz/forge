#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
  STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
}

@test "tracking-contract: orchestrator references tracking-ops.sh" {
  grep -q "tracking-ops.sh" "$ORCHESTRATOR"
}

@test "tracking-contract: orchestrator creates worktree at PREFLIGHT" {
  grep -q "Create Worktree" "$ORCHESTRATOR"
  # The worktree section should be near the other 3.x sections (PREFLIGHT)
  grep -B2 "Create Worktree" "$ORCHESTRATOR" | grep -q "3\.[0-9]\|Stage 0\|PREFLIGHT"
}

@test "tracking-contract: orchestrator has sub-agent dispatch pattern" {
  grep -q "Sub-Agent Dispatch Pattern" "$ORCHESTRATOR"
}

@test "tracking-contract: orchestrator wraps Agent dispatch with TaskCreate" {
  grep -q "TaskCreate.*Dispatching\|Wrap.*TaskCreate" "$ORCHESTRATOR"
}

@test "tracking-contract: orchestrator has kanban transitions table" {
  grep -q "Kanban Status Transitions" "$ORCHESTRATOR"
}

@test "tracking-contract: orchestrator stores ticket_id in state.json" {
  grep -q "ticket_id" "$ORCHESTRATOR"
}

@test "tracking-contract: orchestrator stores branch_name in state.json" {
  grep -q "branch_name" "$ORCHESTRATOR"
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
