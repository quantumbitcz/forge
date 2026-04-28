#!/usr/bin/env bats

@test "forge-config template contains speculation block" {
  local tmpl="$BATS_TEST_DIRNAME/../../modules/frameworks/spring/forge-config-template.md"
  grep -q "^speculation:" "$tmpl"
  grep -q "  enabled: true" "$tmpl"
  grep -q "  candidates_max: 3" "$tmpl"
  grep -q "  auto_pick_threshold_delta: 5" "$tmpl"
  grep -q "  token_ceiling_multiplier: 2.5" "$tmpl"
  grep -q "  min_diversity_score: 0.15" "$tmpl"
  grep -q "  emphasis_axes:" "$tmpl"
  grep -q "  skip_in_modes:" "$tmpl"
}

@test "preflight-constraints documents speculation validation" {
  local doc="$BATS_TEST_DIRNAME/../../shared/preflight-constraints.md"
  grep -q "candidates_max in \[2,5\]" "$doc"
  grep -q "auto_pick_threshold_delta in \[1,20\]" "$doc"
  grep -q "token_ceiling_multiplier in \[1.5, 4.0\]" "$doc"
  grep -q "min_diversity_score in \[0.05, 0.50\]" "$doc"
  grep -q "emphasis_axes length >= candidates_max" "$doc"
}
