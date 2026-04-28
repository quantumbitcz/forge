#!/usr/bin/env bats
# Contract tests for compression metrics in /forge-ask insights.

load '../helpers/test-helpers'

# Extract the `### Subcommand: insights` block from skills/forge-ask/SKILL.md.
_insights_block() {
  awk '
    /^### Subcommand: insights$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$PLUGIN_ROOT/skills/forge-ask/SKILL.md"
}

@test "forge-ask insights references Compression Effectiveness category" {
  _insights_block | grep -q "Compression Effectiveness"
}

@test "forge-ask insights Category 6 mentions output compression savings" {
  _insights_block | grep -q 'output compression\|Output Compression\|output_tokens_per_agent'
}

@test "forge-ask insights Category 6 mentions drift detection" {
  _insights_block | grep -q -i 'drift'
}

@test "forge-ask insights Category 6 mentions input compression savings" {
  _insights_block | grep -q 'input compression\|Input Compression\|original.md'
}

@test "forge-ask insights Category 6 mentions caveman mode" {
  _insights_block | grep -q -i 'caveman'
}

@test "forge-ask insights mentions compression_level_distribution data source" {
  _insights_block | grep -q 'compression_level_distribution'
}

@test "forge-ask insights recommendations include compression drift" {
  _insights_block | grep -q -i 'compression drift\|drifting'
}

# Phase 1 (v3.0.0): caveman skill was removed and forge-compress was rewritten as
# a 4-subcommand entry point (agents|output|status|help). Research-backing and
# arXiv citation assertions no longer apply — the new skill is a concise surface
# over existing compression primitives. See shared/skill-contract.md.
