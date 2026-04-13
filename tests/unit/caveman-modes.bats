#!/usr/bin/env bash

setup() {
  load '../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../skills"
}

@test "caveman-modes: forge-caveman skill exists" {
  assert [ -f "$SKILLS_DIR/forge-caveman/SKILL.md" ]
}

@test "caveman-modes: skill defines 4 modes (lite, full, ultra, off)" {
  local skill="$SKILLS_DIR/forge-caveman/SKILL.md"
  for mode in lite full ultra off; do
    run grep -q "$mode" "$skill"
    assert_success
  done
}

@test "caveman-modes: skill defines auto-clarity exceptions" {
  run grep -i 'auto-clarity\|exception\|suspend' "$SKILLS_DIR/forge-caveman/SKILL.md"
  assert_success
}

@test "caveman-modes: skill has valid frontmatter" {
  run head -1 "$SKILLS_DIR/forge-caveman/SKILL.md"
  assert_output "---"
}

@test "caveman-modes: skill name matches directory" {
  run sed -n 's/^name: *//p' "$SKILLS_DIR/forge-caveman/SKILL.md"
  assert_output "forge-caveman"
}
