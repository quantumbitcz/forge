#!/usr/bin/env bats

# Post-Mega-B (v5.0.0): /forge-commit was retired and is now the `commit`
# subcommand inside skills/forge/SKILL.md. Tests now extract the subcommand
# block and assert against it. Per-skill assertions (50-char limit,
# Co-Authored-By guard, presents-options dialog) that lived in the deleted
# skill body are no longer SKILL.md surface — they belong to the underlying
# git/commit conventions documented in CLAUDE.md and are out of scope here.

load '../../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"
SKILL_FILE="$SKILLS_DIR/forge/SKILL.md"

# Extract the `### Subcommand: commit` block from skills/forge/SKILL.md.
_commit_subcommand_block() {
  awk '
    /^### Subcommand: commit$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$SKILL_FILE"
}

@test "forge-commit: parent /forge SKILL.md exists" {
  assert [ -f "$SKILL_FILE" ]
}

@test "forge-commit: commit subcommand is dispatched" {
  run grep -q '^### Subcommand: commit$' "$SKILL_FILE"
  assert_success
}

@test "forge-commit: parent skill frontmatter name is 'forge'" {
  run grep -m1 '^name: forge$' "$SKILL_FILE"
  assert_success
}

@test "forge-commit: does NOT have disable-model-invocation" {
  run grep -c 'disable-model-invocation' "$SKILL_FILE"
  assert_failure
}

@test "forge-commit: subcommand documents staged changes prerequisite" {
  run bash -c "$(declare -f _commit_subcommand_block); SKILL_FILE='$SKILL_FILE'; _commit_subcommand_block | grep -qi 'staged\|git diff.*cached\|git add'"
  assert_success
}

@test "forge-commit: subcommand uses Conventional Commits format" {
  run bash -c "$(declare -f _commit_subcommand_block); SKILL_FILE='$SKILL_FILE'; _commit_subcommand_block | grep -qi 'conventional commit\|type(scope)\|feat\|fix\|refactor'"
  assert_success
}

@test "forge-commit: subcommand presents options to user via AskUserQuestion" {
  run bash -c "$(declare -f _commit_subcommand_block); SKILL_FILE='$SKILL_FILE'; _commit_subcommand_block | grep -qi 'option\|AskUserQuestion'"
  assert_success
}
