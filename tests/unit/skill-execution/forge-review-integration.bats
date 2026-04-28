#!/usr/bin/env bats

# Post-Mega-B (v5.0.0): /forge-review was retired and is now the `review`
# subcommand inside skills/forge/SKILL.md. The reviewer fan-out (fg-410..419)
# moved to fg-400-quality-gate's own agent file; the skill no longer
# enumerates individual reviewers — it dispatches to the quality gate which
# owns batching. We still verify scope/--full/--fix flags and dispatch
# target are documented at the skill surface.

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  SKILL_FILE="$SKILLS_DIR/forge/SKILL.md"
}

# Extract the `### Subcommand: review` block.
_review_subcommand_block() {
  awk '
    /^### Subcommand: review$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$SKILL_FILE"
}

@test "forge-review-integration: review subcommand dispatches to quality gate" {
  run bash -c "$(declare -f _review_subcommand_block); SKILL_FILE='$SKILL_FILE'; _review_subcommand_block | grep -q 'fg-400-quality-gate'"
  assert_success
}

@test "forge-review-integration: --full mode is documented" {
  run bash -c "$(declare -f _review_subcommand_block); SKILL_FILE='$SKILL_FILE'; _review_subcommand_block | grep -qi -- '--full'"
  assert_success
}

@test "forge-review-integration: --scope flag is documented (changed|all)" {
  run bash -c "$(declare -f _review_subcommand_block); SKILL_FILE='$SKILL_FILE'; _review_subcommand_block | grep -qE -- '--scope'"
  assert_success
}

@test "forge-review-integration: --fix iterative loop is documented" {
  run bash -c "$(declare -f _review_subcommand_block); SKILL_FILE='$SKILL_FILE'; _review_subcommand_block | grep -qi -- '--fix\|fix loop\|iterative'"
  assert_success
}
