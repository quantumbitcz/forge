#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  SKILL_FILE="$SKILLS_DIR/forge verify/SKILL.md"
}

@test "verify-integration: skill documents forge.local.md prerequisite" {
  run grep -qi 'forge.local.md\|forge-init\|forge\.local\|prerequisit\|config' "$SKILL_FILE"
  assert_success
}

@test "verify-integration: skill documents build/lint/test command execution" {
  # Verify skill references build, lint, and test commands
  run grep -qi 'build' "$SKILL_FILE"
  assert_success
  run grep -qi 'lint' "$SKILL_FILE"
  assert_success
  run grep -qi 'test' "$SKILL_FILE"
  assert_success
}
