#!/usr/bin/env bats
# Contract tests for compression validation integration.

load '../helpers/test-helpers'

@test "forge-compress SKILL.md references compression-validation.py" {
  grep -q 'compression-validation.py' "$PLUGIN_ROOT/skills/forge-compress/SKILL.md"
}

@test "forge-compress SKILL.md has validation step 3a" {
  grep -q '3a\. Validate' "$PLUGIN_ROOT/skills/forge-compress/SKILL.md"
}

@test "forge-compress SKILL.md describes retry logic on validation failure" {
  grep -q 'retry\|retries\|Re-validate' "$PLUGIN_ROOT/skills/forge-compress/SKILL.md"
}

@test "forge-compress SKILL.md describes restore-from-original fallback" {
  grep -q 'original.md.*backup\|restore original' "$PLUGIN_ROOT/skills/forge-compress/SKILL.md"
}
