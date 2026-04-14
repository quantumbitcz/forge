#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  SKILL_FILE="$SKILLS_DIR/forge-compress/SKILL.md"
}

@test "forge-compress-integration: skill documents .original.md backup" {
  run grep -qi '\.original\.md\|backup\|preserve.*original\|original.*preserv' "$SKILL_FILE"
  assert_success
}

@test "forge-compress-integration: skill documents --dry-run" {
  run grep -qi '\-\-dry-run\|dry.run\|preview' "$SKILL_FILE"
  assert_success
}

@test "forge-compress-integration: skill documents --restore" {
  run grep -qi '\-\-restore\|restore\|revert.*original\|original.*revert' "$SKILL_FILE"
  assert_success
}

@test "forge-compress-integration: skill documents frontmatter preservation" {
  run grep -qi 'frontmatter\|name.*description\|preserv.*metadata\|yaml.*front' "$SKILL_FILE"
  assert_success
}
