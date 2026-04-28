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

@test "skill-error-handling: forge pipeline subcommands have error handling" {
  local subs=(run fix review)
  for sc in "${subs[@]}"; do
    run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge/SKILL.md' '$sc' | grep -qi 'error\|fail\|missing\|not found'"
    assert_success
  done
}

@test "skill-error-handling: forge-admin graph subcommand handles missing Neo4j" {
  # Skill consolidation: 5 graph skills merged into /forge-admin graph with positional subcommands.
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge-admin/SKILL.md' graph | grep -qi 'docker\|container\|unavailable\|not running'"
  assert_success
}

@test "skill-error-handling: forge deploy subcommand has rollback guidance" {
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge/SKILL.md' deploy | grep -qi 'rollback\|revert\|fail'"
  assert_success
}
