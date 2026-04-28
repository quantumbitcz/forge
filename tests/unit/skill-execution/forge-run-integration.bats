#!/usr/bin/env bats

load '../../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"
SKILL_FILE="$SKILLS_DIR/forge run/SKILL.md"
FORGE_STATE_SH="$PLUGIN_ROOT/shared/forge-state.sh"

@test "forge-run-integration: skill documents forge.local.md prerequisite" {
  run grep -qi 'forge.local.md\|forge-init\|forge\.local' "$SKILL_FILE"
  assert_success
}

@test "forge-run-integration: skill documents .forge directory creation" {
  run grep -q '\.forge' "$SKILL_FILE"
  assert_success
}

@test "forge-run-integration: forge-state init sets story_state to PREFLIGHT" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$FORGE_STATE_SH" init "test-001" "Test requirement" --forge-dir "$forge_dir"
  assert_success

  local state
  state=$(jq -r '.story_state' "$forge_dir/state.json")
  assert [ "$state" = "PREFLIGHT" ]
}

@test "forge-run-integration: skill documents vague requirement routing to shaper" {
  run grep -qi 'shap\|fg-010\|vague\|unclear' "$SKILL_FILE"
  assert_success
}

@test "forge-run-integration: forge-state init with --mode bugfix sets mode=bugfix" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$FORGE_STATE_SH" init "test-001" "Fix the login bug" --mode bugfix --forge-dir "$forge_dir"
  assert_success

  local mode
  mode=$(jq -r '.mode' "$forge_dir/state.json")
  assert [ "$mode" = "bugfix" ]
}
