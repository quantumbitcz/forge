#!/usr/bin/env bats

load '../../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"
SKILL_FILE="$SKILLS_DIR/forge-fix/SKILL.md"
FORGE_STATE_SH="$PLUGIN_ROOT/shared/forge-state.sh"

@test "forge-fix-integration: skill documents forge.local.md prerequisite" {
  run grep -qi 'forge.local.md\|forge-init\|forge\.local\|prerequisit\|require' "$SKILL_FILE"
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

@test "forge-fix-integration: skill documents ticket ID acceptance" {
  run grep -qi 'ticket\|issue\|ID\|linear\|kanban\|bug' "$SKILL_FILE"
  assert_success
}
