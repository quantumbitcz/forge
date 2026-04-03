#!/usr/bin/env bats
# Contract tests: migration states — validates migration state machine documentation.

load '../helpers/test-helpers'

STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
MIGRATION_SKILL="$PLUGIN_ROOT/skills/migration/SKILL.md"
MIGRATION_PLANNER="$PLUGIN_ROOT/agents/fg-160-migration-planner.md"

# ---------------------------------------------------------------------------
# 1. All 4 migration states documented in state-schema
# ---------------------------------------------------------------------------
@test "migration-states: all 4 migration states in state-schema" {
  local states=(MIGRATING MIGRATION_PAUSED MIGRATION_CLEANUP MIGRATION_VERIFY)
  for state in "${states[@]}"; do
    grep -q "$state" "$STATE_SCHEMA" \
      || fail "Migration state $state not found in state-schema.md"
  done
}

# ---------------------------------------------------------------------------
# 2. Migration mode documented in state-schema
# ---------------------------------------------------------------------------
@test "migration-states: mode=migration documented in state-schema" {
  grep -q '"migration"' "$STATE_SCHEMA" \
    || fail "mode=migration not documented in state-schema.md"
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
@test "migration-states: migration skill references fg-160-migration-planner" {
  grep -q "fg-160-migration-planner" "$MIGRATION_SKILL" \
    || fail "Migration skill does not reference fg-160-migration-planner"
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
@test "migration-states: migration skill documents usage patterns" {
  local patterns=(upgrade check)
  for pattern in "${patterns[@]}"; do
    grep -qi "$pattern" "$MIGRATION_SKILL" \
      || fail "Usage pattern '$pattern' not documented in migration skill"
  done
}

# ---------------------------------------------------------------------------
# 8. Stage contract documents migration state transitions
# ---------------------------------------------------------------------------
@test "migration-states: stage contract references migration states" {
  grep -qi "migrat" "$STAGE_CONTRACT" \
    || fail "Migration not referenced in stage-contract.md"
}
