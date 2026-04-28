#!/usr/bin/env bash

setup() {
  load '../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../skills"
  ADMIN_SKILL="$SKILLS_DIR/forge-admin/SKILL.md"
}

# Extract the `### Subcommand: compress` block from skills/forge-admin/SKILL.md.
_compress_block() {
  awk '
    /^### Subcommand: compress$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$ADMIN_SKILL"
}

@test "compress-output-modes: forge-admin SKILL.md exists with compress subcommand" {
  assert [ -f "$ADMIN_SKILL" ]
  run bash -c "grep -q '^### Subcommand: compress\$' '$ADMIN_SKILL'"
  assert_success
}

@test "compress-output-modes: compress subcommand defines 4 modes (lite, full, ultra, off)" {
  for mode in lite full ultra off; do
    run bash -c "$(declare -f _compress_block); ADMIN_SKILL='$ADMIN_SKILL'; _compress_block | grep -q '$mode'"
    assert_success
  done
}

# Phase 1 (v3.0.0): auto-clarity exceptions moved out of the top-level
# forge-compress SKILL.md and into the underlying compression pipeline. The
# new skill is a concise 4-subcommand surface (agents|output|status|help).

@test "compress-output-modes: forge-admin SKILL.md has valid frontmatter" {
  run head -1 "$ADMIN_SKILL"
  assert_output "---"
}

@test "compress-output-modes: forge-admin skill name matches directory" {
  run sed -n 's/^name: *//p' "$ADMIN_SKILL"
  assert_output "forge-admin"
}
