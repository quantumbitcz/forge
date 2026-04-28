#!/usr/bin/env bats
# Contract tests: migration states — validates migration state machine documentation.

load '../helpers/test-helpers'

STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
STATE_SCHEMA_FIELDS="$PLUGIN_ROOT/shared/state-schema-fields.md"
STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
FORGE_SKILL="$PLUGIN_ROOT/skills/forge/SKILL.md"
MIGRATION_PLANNER="$PLUGIN_ROOT/agents/fg-160-migration-planner.md"

# Extract the `### Subcommand: migrate` block from skills/forge/SKILL.md.
_migrate_subcommand_block() {
  awk '
    /^### Subcommand: migrate$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$FORGE_SKILL"
}

# ---------------------------------------------------------------------------
# 1. All 4 migration states documented in state-schema
# ---------------------------------------------------------------------------
@test "migration-states: all 4 migration states in state-schema" {
  local states=(MIGRATING MIGRATION_PAUSED MIGRATION_CLEANUP MIGRATION_VERIFY)
  for state in "${states[@]}"; do
    grep -qh "$state" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" \
      || fail "Migration state $state not found in state-schema(-fields).md"
  done
}

# ---------------------------------------------------------------------------
# 2. Migration mode documented in state-schema
# ---------------------------------------------------------------------------
@test "migration-states: mode=migration documented in state-schema" {
  grep -qh '"migration"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" \
    || fail "mode=migration not documented in state-schema(-fields).md"
}

# ---------------------------------------------------------------------------
# 3. Migration planner agent exists
# ---------------------------------------------------------------------------
@test "migration-states: fg-160-migration-planner agent exists" {
  [[ -f "$MIGRATION_PLANNER" ]] \
    || fail "fg-160-migration-planner agent file not found"
}

# ---------------------------------------------------------------------------
# 4. Migration planner has Agent tool (dispatches sub-agents)
# ---------------------------------------------------------------------------
@test "migration-states: migration planner has Agent tool" {
  grep -q "Agent" "$MIGRATION_PLANNER" \
    || fail "fg-160-migration-planner missing Agent tool"
}

# ---------------------------------------------------------------------------
# 5. Migration skill exists and references planner
# ---------------------------------------------------------------------------
@test "migration-states: migrate subcommand references fg-160-migration-planner" {
  _migrate_subcommand_block | grep -q "fg-160-migration-planner" \
    || fail "migrate subcommand does not reference fg-160-migration-planner"
}

# ---------------------------------------------------------------------------
# 6. Migration states mentioned in CLAUDE.md
# ---------------------------------------------------------------------------
@test "migration-states: migration states listed in CLAUDE.md" {
  grep -q "MIGRATING" "$CLAUDE_MD" \
    || fail "MIGRATING not mentioned in CLAUDE.md"
  grep -q "MIGRATION_PAUSED" "$CLAUDE_MD" \
    || fail "MIGRATION_PAUSED not mentioned in CLAUDE.md"
}

# ---------------------------------------------------------------------------
# 7. Migration skill supports usage patterns
# ---------------------------------------------------------------------------
@test "migration-states: migrate subcommand documents usage patterns" {
  local block
  block="$(_migrate_subcommand_block)"
  local patterns=(upgrade check)
  for pattern in "${patterns[@]}"; do
    echo "$block" | grep -qi "$pattern" \
      || fail "Usage pattern '$pattern' not documented in migrate subcommand"
  done
}

# ---------------------------------------------------------------------------
# 8. Stage contract documents migration state transitions
# ---------------------------------------------------------------------------
@test "migration-states: stage contract references migration states" {
  grep -qi "migrat" "$STAGE_CONTRACT" \
    || fail "Migration not referenced in stage-contract.md"
}
