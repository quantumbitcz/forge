#!/usr/bin/env bats
# Contract tests for compression metrics in /forge-insights.

load '../helpers/test-helpers'

@test "forge-insights references Compression Effectiveness category" {
  grep -q "Compression Effectiveness" "$PLUGIN_ROOT/skills/forge-insights/SKILL.md"
}

@test "forge-insights Category 6 mentions output compression savings" {
  grep -q 'output compression\|Output Compression\|output_tokens_per_agent' "$PLUGIN_ROOT/skills/forge-insights/SKILL.md"
}

@test "forge-insights Category 6 mentions drift detection" {
  grep -q -i 'drift' "$PLUGIN_ROOT/skills/forge-insights/SKILL.md"
}

@test "forge-insights Category 6 mentions input compression savings" {
  grep -q 'input compression\|Input Compression\|original.md' "$PLUGIN_ROOT/skills/forge-insights/SKILL.md"
}

@test "forge-insights Category 6 mentions caveman mode" {
  grep -q -i 'caveman' "$PLUGIN_ROOT/skills/forge-insights/SKILL.md"
}

@test "forge-insights mentions compression_level_distribution data source" {
  grep -q 'compression_level_distribution' "$PLUGIN_ROOT/skills/forge-insights/SKILL.md"
}

@test "forge-insights recommendations include compression drift" {
  grep -q -i 'compression drift\|drifting' "$PLUGIN_ROOT/skills/forge-insights/SKILL.md"
}

# Phase 1 (v3.0.0): caveman skill was removed and forge-compress was rewritten as
# a 4-subcommand entry point (agents|output|status|help). Research-backing and
# arXiv citation assertions no longer apply — the new skill is a concise surface
# over existing compression primitives. See shared/skill-contract.md.
