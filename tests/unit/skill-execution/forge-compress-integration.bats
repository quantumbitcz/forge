#!/usr/bin/env bats
#
# Phase 1 (v3.0.0) rewrote forge-compress as a 4-subcommand skill
# (agents|output|status|help). The pre-Phase-1 assertions about .original.md
# backup, --restore flag, and frontmatter preservation no longer apply —
# those responsibilities live inside the underlying compression pipeline and
# are no longer documented at the SKILL.md surface. Only the --dry-run flag
# remains user-visible at the skill level.

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  SKILL_FILE="$SKILLS_DIR/forge-admin compress/SKILL.md"
}

@test "forge-compress-integration: skill documents --dry-run" {
  run grep -qi '\-\-dry-run\|dry.run\|preview' "$SKILL_FILE"
  assert_success
}
