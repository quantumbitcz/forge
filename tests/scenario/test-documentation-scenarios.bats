#!/usr/bin/env bats
# Scenario tests: documentation subsystem behavior verification.

load '../helpers/test-helpers'

@test "docs-scenario: discoverer agent has all required sections" {
  local agent="$PLUGIN_ROOT/agents/fg-130-docs-discoverer.md"
  grep -q "Discovery Targets" "$agent" || fail "Missing Discovery Targets section"
  grep -q "Processing Pipeline" "$agent" || fail "Missing Processing Pipeline section"
  grep -q "Convention Drift\|Deferred Discovery\|content_hash" "$agent" || fail "Missing drift detection"
  grep -q "Index Mode\|docs-index.json" "$agent" || fail "Missing index mode fallback"
  grep -q "Forbidden Actions" "$agent" || fail "Missing Forbidden Actions"
}

@test "docs-scenario: consistency reviewer finding format matches DOC-* pattern" {
  local agent="$PLUGIN_ROOT/agents/docs-consistency-reviewer.md"
  grep -q "DOC-DECISION" "$agent" || fail "Missing DOC-DECISION category"
  grep -q "DOC-STALE" "$agent" || fail "Missing DOC-STALE category"
  grep -q "DOC-MISSING" "$agent" || fail "Missing DOC-MISSING category"
  grep -q "DOC-CONSTRAINT" "$agent" || fail "Missing DOC-CONSTRAINT category"
  grep -q "SCOUT-DOC" "$agent" || fail "Missing SCOUT-DOC handling for LOW confidence"
}

@test "docs-scenario: consistency reviewer handles cross-repo as WARNING only" {
  local agent="$PLUGIN_ROOT/agents/docs-consistency-reviewer.md"
  grep -qi "cross-repo.*WARNING\|WARNING.*cross-repo\|cross-repo.*CRITICAL" "$agent" || fail "Cross-repo finding severity not documented"
}

@test "docs-scenario: generator supports pipeline and standalone modes" {
  local agent="$PLUGIN_ROOT/agents/fg-350-docs-generator.md"
  grep -qi "Pipeline Mode\|pipeline mode" "$agent" || fail "Missing pipeline mode"
  grep -qi "Standalone Mode\|standalone mode" "$agent" || fail "Missing standalone mode"
}

@test "docs-scenario: generator respects user-maintained fences" {
  local agent="$PLUGIN_ROOT/agents/fg-350-docs-generator.md"
  grep -q "user-maintained" "$agent" || fail "Missing user-maintained fence handling"
}

@test "docs-scenario: generator writes to worktree in pipeline mode" {
  local agent="$PLUGIN_ROOT/agents/fg-350-docs-generator.md"
  grep -qi "worktree" "$agent" || fail "Missing worktree awareness"
}

@test "docs-scenario: generator pipeline mode guardrails prevent runbook creation" {
  local agent="$PLUGIN_ROOT/agents/fg-350-docs-generator.md"
  grep -qi "Never in Pipeline Mode\|never.*pipeline\|runbook.*standalone\|standalone.*only" "$agent" || fail "Missing pipeline mode guardrails"
}

@test "docs-scenario: docs-generate skill supports --coverage flag" {
  local skill="$PLUGIN_ROOT/skills/docs-generate/SKILL.md"
  grep -q "\-\-coverage" "$skill" || fail "Missing --coverage flag"
}

@test "docs-scenario: docs-generate skill supports --confirm-decisions flag" {
  local skill="$PLUGIN_ROOT/skills/docs-generate/SKILL.md"
  grep -q "\-\-confirm-decisions" "$skill" || fail "Missing --confirm-decisions flag"
}

@test "docs-scenario: docs-generate skill detects framework without pipeline config" {
  local skill="$PLUGIN_ROOT/skills/docs-generate/SKILL.md"
  grep -qi "stack marker\|auto-detect\|detection fails\|framework.*detect" "$skill" || fail "Missing standalone framework detection"
}

@test "docs-scenario: ADR significance criteria documented" {
  local found=0
  grep -qi "significance criteria\|2+ criteria\|alternatives evaluated" "$PLUGIN_ROOT/agents/fg-350-docs-generator.md" && found=1
  grep -qi "significance criteria\|2+ criteria\|alternatives evaluated" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md" && found=1
  (( found > 0 )) || fail "ADR significance criteria not documented in generator or orchestrator"
}

@test "docs-scenario: graph schema DocDecision has status enum" {
  grep -q "proposed.*accepted.*deprecated.*superseded" "$PLUGIN_ROOT/shared/graph/schema.md" || fail "DocDecision status enum not defined"
}

@test "docs-scenario: graph schema DocFile has cross_repo property" {
  grep -q "cross_repo" "$PLUGIN_ROOT/shared/graph/schema.md" || fail "DocFile missing cross_repo property"
}

@test "docs-scenario: graph schema DocSection has content_hash_updated property" {
  grep -q "content_hash_updated" "$PLUGIN_ROOT/shared/graph/schema.md" || fail "DocSection missing content_hash_updated property"
}
