#!/usr/bin/env bats
# Contract tests: documentation subsystem integration contracts.

load '../helpers/test-helpers'

ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
VALIDATOR="$PLUGIN_ROOT/agents/fg-210-validator.md"
QUALITY_GATE="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
GRAPH_SCHEMA="$PLUGIN_ROOT/shared/graph/schema.md"
QUERY_PATTERNS="$PLUGIN_ROOT/shared/graph/query-patterns.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
SCORING="$PLUGIN_ROOT/shared/scoring.md"

@test "docs-contract: orchestrator dispatches fg-130-docs-discoverer at PREFLIGHT" {
  grep -q "fg-130-docs-discoverer" "$ORCHESTRATOR" || fail "Orchestrator does not reference fg-130-docs-discoverer"
}

@test "docs-contract: orchestrator dispatches fg-350-docs-generator at DOCUMENTING" {
  grep -q "fg-350-docs-generator" "$ORCHESTRATOR" || fail "Orchestrator does not reference fg-350-docs-generator"
}

@test "docs-contract: stage contract Stage 0 includes fg-130-docs-discoverer" {
  grep -q "fg-130-docs-discoverer" "$STAGE_CONTRACT" || fail "Stage contract Stage 0 does not include fg-130-docs-discoverer"
}

@test "docs-contract: stage contract Stage 7 agent is fg-350-docs-generator" {
  grep -q "fg-350-docs-generator" "$STAGE_CONTRACT" || fail "Stage contract Stage 7 does not reference fg-350-docs-generator"
  local stage7_line
  stage7_line="$(grep "| 7 |" "$STAGE_CONTRACT")"
  [[ "$stage7_line" != *"| inline |"* ]] || fail "Stage 7 is still marked as inline"
}

@test "docs-contract: state schema version is 1.4.0" {
  grep -q '"1.4.0"' "$STATE_SCHEMA" || fail "State schema version is not 1.4.0"
}

@test "docs-contract: state schema includes documentation field" {
  grep -q '"documentation"' "$STATE_SCHEMA" || fail "State schema missing documentation field"
  grep -q "last_discovery_timestamp" "$STATE_SCHEMA" || fail "Missing last_discovery_timestamp"
  grep -q "files_discovered" "$STATE_SCHEMA" || fail "Missing files_discovered"
  grep -q "generation_history" "$STATE_SCHEMA" || fail "Missing generation_history"
}

@test "docs-contract: graph schema includes Doc* node types" {
  local required_nodes=(DocFile DocSection DocDecision DocConstraint DocDiagram)
  local missing=()
  for node in "${required_nodes[@]}"; do
    grep -q "$node" "$GRAPH_SCHEMA" || missing+=("$node")
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Graph schema missing node types: ${missing[*]}"
  fi
}

@test "docs-contract: graph schema includes all 8 new relationships" {
  local required_rels=(DESCRIBES SECTION_OF DECIDES CONSTRAINS CONTRADICTS DIAGRAMS SUPERSEDES DOC_IMPORTS)
  local missing=()
  for rel in "${required_rels[@]}"; do
    grep -q "$rel" "$GRAPH_SCHEMA" || missing+=("$rel")
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Graph schema missing relationships: ${missing[*]}"
  fi
}

@test "docs-contract: query patterns include 5 documentation queries" {
  local required_queries=("Documentation Impact" "Stale Docs Detection" "Decision Traceability" "Contradiction Report" "Documentation Coverage Gap")
  local missing=()
  for query in "${required_queries[@]}"; do
    grep -q "$query" "$QUERY_PATTERNS" || missing+=("$query")
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Query patterns missing: ${missing[*]}"
  fi
}

@test "docs-contract: scoring handles DOC-* finding categories" {
  grep -q "DOC-DECISION" "$SCORING" || fail "Scoring missing DOC-DECISION"
  grep -q "DOC-CONSTRAINT" "$SCORING" || fail "Scoring missing DOC-CONSTRAINT"
  grep -q "DOC-STALE" "$SCORING" || fail "Scoring missing DOC-STALE"
  grep -q "DOC-MISSING" "$SCORING" || fail "Scoring missing DOC-MISSING"
  grep -q "DOC-DIAGRAM" "$SCORING" || fail "Scoring missing DOC-DIAGRAM"
  grep -q "DOC-CROSSREF" "$SCORING" || fail "Scoring missing DOC-CROSSREF"
}

@test "docs-contract: scoring handles SCOUT-DOC-* for LOW confidence" {
  grep -q "SCOUT-DOC" "$SCORING" || fail "Scoring missing SCOUT-DOC-* handling"
}

@test "docs-contract: validator has 7 perspectives including documentation_consistency" {
  grep -q "documentation_consistency" "$VALIDATOR" || fail "Validator missing documentation_consistency perspective"
}

@test "docs-contract: quality gate references fg-418-docs-consistency-reviewer" {
  grep -q "fg-418-docs-consistency-reviewer" "$QUALITY_GATE" || fail "Quality gate does not reference fg-418-docs-consistency-reviewer"
}

@test "docs-contract: docs-index.json documented in state schema" {
  grep -q "docs-index.json" "$STATE_SCHEMA" || fail "State schema does not document docs-index.json"
}

@test "docs-contract: forge-init templates include documentation config" {
  local missing=()
  for tmpl in "$PLUGIN_ROOT"/modules/frameworks/*/local-template.md; do
    grep -q "documentation:" "$tmpl" || missing+=("$(basename "$(dirname "$tmpl")")")
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Templates missing documentation: config: ${missing[*]}"
  fi
}
