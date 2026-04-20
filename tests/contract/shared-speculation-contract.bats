#!/usr/bin/env bats

@test "shared/speculation.md exists" {
  [ -f "$BATS_TEST_DIRNAME/../../shared/speculation.md" ]
}

@test "shared/speculation.md contains all required sections" {
  local doc="$BATS_TEST_DIRNAME/../../shared/speculation.md"
  grep -q "^## Trigger Logic" "$doc"
  grep -q "^## Dispatch Protocol" "$doc"
  grep -q "^## Diversity Check" "$doc"
  grep -q "^## Cost Guardrails" "$doc"
  grep -q "^## Selection" "$doc"
  grep -q "^## Persistence" "$doc"
  grep -q "^## Eval Methodology" "$doc"
  grep -q "^## Forbidden Actions" "$doc"
}

@test "shared/speculation.md documents min_diversity_score" {
  grep -q "min_diversity_score" "$BATS_TEST_DIRNAME/../../shared/speculation.md"
}

@test "shared/speculation.md documents token_ceiling_multiplier formula" {
  grep -q "estimated = baseline + (mean(recent_planner_tokens" "$BATS_TEST_DIRNAME/../../shared/speculation.md"
}

@test "shared/speculation.md documents OR semantics for ambiguity signals" {
  grep -q "triggered = (confidence == MEDIUM) AND" "$BATS_TEST_DIRNAME/../../shared/speculation.md"
}

@test "confidence-scoring references speculation MEDIUM trigger" {
  grep -q "speculation" "$BATS_TEST_DIRNAME/../../shared/confidence-scoring.md"
}

@test "agent-role-hierarchy notes N-way parallel PLAN dispatch" {
  grep -q "speculat" "$BATS_TEST_DIRNAME/../../shared/agent-role-hierarchy.md"
}

@test "CLAUDE.md has Phase 12 feature-table entry" {
  grep -q "Speculative.*plan branches" "$BATS_TEST_DIRNAME/../../CLAUDE.md"
}

@test "plugin.json version 3.5.0" {
  grep -q '"version": "3.5.0"' "$BATS_TEST_DIRNAME/../../.claude-plugin/plugin.json"
}

@test "marketplace.json version 3.5.0" {
  grep -q '"version": "3.5.0"' "$BATS_TEST_DIRNAME/../../.claude-plugin/marketplace.json"
}
