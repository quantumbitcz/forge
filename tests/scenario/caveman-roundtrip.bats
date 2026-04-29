#!/usr/bin/env bash
#
# Phase 1 (v3.0.0): forge-compress was rewritten as a 4-subcommand skill
# (agents|output|status|help). The pre-Phase-1 flags (--restore, --level,
# --scope) and `.original.md` backup rule were moved into the underlying
# compression pipeline and are no longer documented at the SKILL.md surface.
# Only --dry-run remains a user-visible contract at the skill level.

# Covers:

setup() {
  load '../helpers/test-helpers'
  ADMIN_SKILL="$BATS_TEST_DIRNAME/../../skills/forge-admin/SKILL.md"
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

@test "caveman-roundtrip: forge-admin compress subcommand documents --dry-run flag" {
  run bash -c "$(declare -f _compress_block); ADMIN_SKILL='$ADMIN_SKILL'; _compress_block | grep -q -- '--dry-run'"
  assert_success
}

@test "caveman-roundtrip: forge-admin compress subcommand documents output verb modes" {
  # Phase 1: 4 output modes (off, lite, full, ultra) must be documented
  for mode in off lite full ultra; do
    run bash -c "$(declare -f _compress_block); ADMIN_SKILL='$ADMIN_SKILL'; _compress_block | grep -q '$mode'"
    assert_success
  done
}
