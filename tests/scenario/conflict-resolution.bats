#!/usr/bin/env bats
# Scenario tests: reviewer conflict resolution end-to-end behavior

# Covers:

load '../helpers/test-helpers'

AGENT_COMM="$PLUGIN_ROOT/shared/agent-communication.md"
QUALITY_GATE="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
SCORING="$PLUGIN_ROOT/shared/scoring.md"

# ---------------------------------------------------------------------------
# 1. Priority ordering has 6 levels
# ---------------------------------------------------------------------------
@test "conflict-scenario: priority ordering has 6 levels" {
  local count
  count=$(grep -cE '^\s*[0-9]+\.\s+\*\*' "$AGENT_COMM" | head -1)
  # Extract lines within the Conflict Reporting Protocol section that look like
  # numbered priority items (e.g., "1. **Security**")
  local section
  section=$(sed -n '/### Conflict Reporting Protocol/,/^##/p' "$AGENT_COMM")
  local level_count
  level_count=$(echo "$section" | grep -cE '^\s*[0-9]+\.\s+\*\*')
  [[ "$level_count" -eq 6 ]] \
    || fail "Expected 6 priority levels, found $level_count"

  # Verify specific level names
  echo "$section" | grep -q "Security" || fail "Security level missing"
  echo "$section" | grep -q "Architecture" || fail "Architecture level missing"
  echo "$section" | grep -q "Code Quality" || fail "Code Quality level missing"
  echo "$section" | grep -q "Performance" || fail "Performance level missing"
  echo "$section" | grep -q "Convention" || fail "Convention level missing"
  echo "$section" | grep -q "Style" || fail "Style level missing"
}

# ---------------------------------------------------------------------------
# 2. Demoted findings use SCOUT prefix
# ---------------------------------------------------------------------------
@test "conflict-scenario: demoted findings use SCOUT-CONFLICT prefix" {
  grep -q "SCOUT-CONFLICT" "$QUALITY_GATE" \
    || fail "SCOUT-CONFLICT prefix not documented in quality gate"
}

# ---------------------------------------------------------------------------
# 3. Conflicts recorded in stage notes
# ---------------------------------------------------------------------------
@test "conflict-scenario: conflicts recorded in stage notes" {
  grep -qi "stage.notes\|stage notes" "$QUALITY_GATE" \
    || fail "Quality gate does not mention stage notes for conflict recording"
  # The conflict detection section should mention recording/documenting conflicts
  local section
  section=$(sed -n '/## 6.1 Conflict Detection/,/^---/p' "$QUALITY_GATE")
  echo "$section" | grep -qi "stage.notes\|report\|record\|document" \
    || fail "Conflict detection section does not mention recording conflicts"
}

# ---------------------------------------------------------------------------
# 4. SCOUT findings excluded from scoring (cross-reference scoring.md)
# ---------------------------------------------------------------------------
@test "conflict-scenario: SCOUT findings excluded from scoring" {
  grep -q "SCOUT-\*.*excluded from.*scoring\|SCOUT-\*.*no.*deduction\|SCOUT.*excluded.*scoring" "$SCORING" \
    || fail "SCOUT-* exclusion not documented in scoring.md"
}
