#!/usr/bin/env bats

# Post-Mega-B (v5.0.0): /forge-verify was retired and is now the `verify`
# subcommand inside skills/forge/SKILL.md. forge.local.md gating lives in
# the shared prerequisites block at the top of that file. The verify
# subcommand documents --build/--config/--all flags.

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  SKILL_FILE="$SKILLS_DIR/forge/SKILL.md"
}

# Extract the `### Subcommand: verify` block.
_verify_subcommand_block() {
  awk '
    /^### Subcommand: verify$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$SKILL_FILE"
}

@test "verify-integration: parent /forge skill documents forge.local.md prerequisite" {
  run grep -qi 'forge.local.md\|forge\.local' "$SKILL_FILE"
  assert_success
}

@test "verify-integration: verify subcommand documents build/lint/test" {
  run bash -c "$(declare -f _verify_subcommand_block); SKILL_FILE='$SKILL_FILE'; _verify_subcommand_block | grep -qi 'build'"
  assert_success
  run bash -c "$(declare -f _verify_subcommand_block); SKILL_FILE='$SKILL_FILE'; _verify_subcommand_block | grep -qi 'lint'"
  assert_success
  run bash -c "$(declare -f _verify_subcommand_block); SKILL_FILE='$SKILL_FILE'; _verify_subcommand_block | grep -qi 'test'"
  assert_success
}
