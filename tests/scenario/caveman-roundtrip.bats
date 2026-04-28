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
  COMPRESS_SKILL="$BATS_TEST_DIRNAME/../../skills/forge-admin compress/SKILL.md"
}

@test "caveman-roundtrip: forge-compress documents --dry-run flag" {
  run grep -q '\-\-dry-run' "$COMPRESS_SKILL"
  assert_success
}

@test "caveman-roundtrip: forge-compress documents output subcommand modes" {
  # Phase 1: 4 output modes (off, lite, full, ultra) must be documented
  for mode in off lite full ultra; do
    run grep -q "$mode" "$COMPRESS_SKILL"
    assert_success
  done
}
