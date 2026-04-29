#!/usr/bin/env bats

# Post-Mega-B (v5.0.0): /forge-run was retired and is now the `run`
# subcommand inside skills/forge/SKILL.md. forge.local.md gating lives in
# the shared prerequisites block at the top of that file (not duplicated
# per-subcommand). Tests extract subcommand body where the assertion is
# subcommand-specific; otherwise they grep the parent skill.

load '../../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"
SKILL_FILE="$SKILLS_DIR/forge/SKILL.md"
FORGE_STATE_SH="$PLUGIN_ROOT/shared/forge-state.sh"

# Extract the `### Subcommand: run` block.
_run_subcommand_block() {
  awk '
    /^### Subcommand: run$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$SKILL_FILE"
}

@test "forge-run-integration: parent /forge skill documents forge.local.md prerequisite" {
  run grep -qi 'forge.local.md\|forge\.local' "$SKILL_FILE"
  assert_success
}

@test "forge-run-integration: parent /forge skill documents .forge directory creation" {
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

@test "forge-run-integration: run subcommand documents vague requirement routing to shaper" {
  run bash -c "$(declare -f _run_subcommand_block); SKILL_FILE='$SKILL_FILE'; _run_subcommand_block | grep -qi 'shap\|fg-010\|vague\|unclear'"
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
