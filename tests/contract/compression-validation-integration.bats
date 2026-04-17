#!/usr/bin/env bats
# Contract tests for compression validation integration.
#
# Phase 1 (v3.0.0): forge-compress was rewritten as a 4-subcommand skill
# (agents|output|status|help). The pre-Phase-1 assertions about .original.md
# backup, --restore, validation step 3a, and retry-on-validation-failure no
# longer apply — those responsibilities have moved into the underlying
# compression pipeline and are no longer documented in the top-level SKILL.md.
# Only the --dry-run flag remains a user-visible contract at the skill level.

load '../helpers/test-helpers'

@test "forge-compress SKILL.md documents --dry-run flag" {
  grep -q -- '--dry-run' "$PLUGIN_ROOT/skills/forge-compress/SKILL.md"
}
