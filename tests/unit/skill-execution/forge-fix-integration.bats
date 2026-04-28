#!/usr/bin/env bats

load '../../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"
SKILL_FILE="$SKILLS_DIR/forge/SKILL.md"
FORGE_STATE_SH="$PLUGIN_ROOT/shared/forge-state.sh"

# Extract the `### Subcommand: fix` block from skills/forge/SKILL.md.
_fix_subcommand_block() {
  awk '
    /^### Subcommand: fix$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$SKILL_FILE"
}

@test "forge-fix-integration: fix subcommand documents forge.local.md prerequisite" {
  run bash -c "$(declare -f _fix_subcommand_block); SKILL_FILE='$SKILL_FILE'; _fix_subcommand_block | grep -qi 'forge.local.md\|forge-init\|forge\.local\|prerequisit\|require'"
  assert_success
}

@test "forge-fix-integration: forge-state init bugfix mode sets mode=bugfix" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$FORGE_STATE_SH" init "BUG-001" "Reproduce and fix" --mode bugfix --forge-dir "$forge_dir"
  assert_success

  local mode
  mode=$(jq -r '.mode' "$forge_dir/state.json")
  assert [ "$mode" = "bugfix" ]
}

@test "forge-fix-integration: fix subcommand documents ticket ID acceptance" {
  run bash -c "$(declare -f _fix_subcommand_block); SKILL_FILE='$SKILL_FILE'; _fix_subcommand_block | grep -qi 'ticket\|issue\|ID\|linear\|kanban\|bug'"
  assert_success
}
