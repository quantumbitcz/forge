#!/usr/bin/env bash

setup() {
  load '../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../skills"
}

@test "compress-output-modes: /forge-compress output skill exists" {
  assert [ -f "$SKILLS_DIR/forge-compress/SKILL.md" ]
}

@test "compress-output-modes: skill defines 4 modes (lite, full, ultra, off)" {
  local skill="$SKILLS_DIR/forge-compress/SKILL.md"
  for mode in lite full ultra off; do
    run grep -q "$mode" "$skill"
    assert_success
  done
}

# Phase 1 (v3.0.0): auto-clarity exceptions moved out of the top-level
# forge-compress SKILL.md and into the underlying compression pipeline. The
# new skill is a concise 4-subcommand surface (agents|output|status|help).

@test "compress-output-modes: skill has valid frontmatter" {
  run head -1 "$SKILLS_DIR/forge-compress/SKILL.md"
  assert_output "---"
}

@test "compress-output-modes: skill name matches directory" {
  run sed -n 's/^name: *//p' "$SKILLS_DIR/forge-compress/SKILL.md"
  assert_output "forge-compress"
}
