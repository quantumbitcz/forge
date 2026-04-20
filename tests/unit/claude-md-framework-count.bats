#!/usr/bin/env bats
# Phase 08: asserts CLAUDE.md framework count string matches MIN_FRAMEWORKS.

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../.."
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"

load "${BATS_TEST_DIRNAME}/../lib/module-lists.bash"

@test "CLAUDE.md exists" {
  [ -f "$CLAUDE_MD" ]
}

@test "CLAUDE.md framework count matches MIN_FRAMEWORKS" {
  local count
  count=$(grep -oE '`frameworks/` \([0-9]+\)' "$CLAUDE_MD" | head -1 | grep -oE '[0-9]+')
  [ -n "$count" ]
  [ "$count" = "$MIN_FRAMEWORKS" ]
}

@test "CLAUDE.md framework list includes flask, laravel, rails" {
  grep -q 'flask' "$CLAUDE_MD"
  grep -q 'laravel' "$CLAUDE_MD"
  grep -q 'rails' "$CLAUDE_MD"
}
