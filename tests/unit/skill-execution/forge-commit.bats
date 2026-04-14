#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  SKILL_FILE="$SKILLS_DIR/forge-commit/SKILL.md"
}

@test "forge-commit: SKILL.md exists" {
  assert_file_exists "$SKILL_FILE"
}

@test "forge-commit: frontmatter has correct name" {
  run grep -m1 '^name: forge-commit' "$SKILL_FILE"
  assert_success
}

@test "forge-commit: does NOT have disable-model-invocation" {
  run grep -c 'disable-model-invocation' "$SKILL_FILE"
  assert_failure
}

@test "forge-commit: documents git repo prerequisite" {
  run grep -qi 'git.*repo\|rev-parse\|git repository' "$SKILL_FILE"
  assert_success
}

@test "forge-commit: documents staged changes prerequisite" {
  run grep -qi 'staged\|git diff.*cached\|git add' "$SKILL_FILE"
  assert_success
}

@test "forge-commit: uses Conventional Commits format" {
  run grep -qi 'conventional commit\|type(scope)\|feat\|fix\|refactor' "$SKILL_FILE"
  assert_success
}

@test "forge-commit: enforces 50 char subject limit" {
  run grep -qi '50.*char\|50 char\|<=50\|maximum 50' "$SKILL_FILE"
  assert_success
}

@test "forge-commit: NEVER includes Co-Authored-By or AI attribution" {
  run grep -qi 'never.*co-authored\|never.*ai.*attribution\|never.*attribution' "$SKILL_FILE"
  assert_success
}

@test "forge-commit: presents options to user (commit/edit/cancel)" {
  run grep -qi 'commit.*edit.*cancel\|commit as-is\|edit message\|cancel' "$SKILL_FILE"
  assert_success
}
