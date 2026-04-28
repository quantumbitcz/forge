#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

# Extract a `### Subcommand: <name>` block from a consolidated SKILL.md.
_subcommand_block() {
  local skill_file="$1" name="$2"
  awk -v name="$name" '
    $0 ~ "^### Subcommand: " name "$" { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$skill_file"
}

@test "skill-prerequisites: forge pipeline subcommands document prerequisites" {
  local subs=(run fix sprint review)
  for sc in "${subs[@]}"; do
    run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge/SKILL.md' '$sc' | grep -qi 'prerequisit\|before\|require\|must\|STOP'"
    assert_success
  done
}

@test "skill-prerequisites: forge skill checks for existing config" {
  run grep -qi 'forge.local\|existing\|already' "$SKILLS_DIR/forge/SKILL.md"
  assert_success
}

@test "skill-prerequisites: forge-admin recover subcommand checks for state.json" {
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge-admin/SKILL.md' recover | grep -qi 'state\.json\|checkpoint\|aborted'"
  assert_success
}

@test "skill-prerequisites: forge deploy subcommand checks for dirty tree" {
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge/SKILL.md' deploy | grep -qi 'dirty\|uncommit\|clean'"
  assert_success
}
