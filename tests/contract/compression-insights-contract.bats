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

@test "caveman SKILL.md references arXiv:2604.00025" {
  grep -q "2604.00025" "$PLUGIN_ROOT/skills/forge-compress/SKILL.md"
}

@test "caveman SKILL.md has Research Backing section" {
  grep -q "Research Backing" "$PLUGIN_ROOT/skills/forge-compress/SKILL.md"
}
