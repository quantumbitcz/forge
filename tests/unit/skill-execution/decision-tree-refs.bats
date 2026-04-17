#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

@test "decision-tree: forge-help skill exists" {
  assert [ -f "$SKILLS_DIR/forge-help/SKILL.md" ]
}

@test "decision-tree: references forge-run" {
  run grep -q 'forge-run' "$SKILLS_DIR/forge-help/SKILL.md"
  assert_success
}

@test "decision-tree: references forge-fix" {
  run grep -q 'forge-fix' "$SKILLS_DIR/forge-help/SKILL.md"
  assert_success
}

@test "decision-tree: references forge-review" {
  run grep -q 'forge-review' "$SKILLS_DIR/forge-help/SKILL.md"
  assert_success
}

@test "decision-tree: references forge-compress" {
  run grep -q 'forge-compress' "$SKILLS_DIR/forge-help/SKILL.md"
  assert_success
}

@test "decision-tree: has valid frontmatter" {
  run head -1 "$SKILLS_DIR/forge-help/SKILL.md"
  assert_output "---"
  run sed -n 's/^name: *//p' "$SKILLS_DIR/forge-help/SKILL.md"
  assert_output "forge-help"
}
