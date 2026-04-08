#!/usr/bin/env bats
# Contract tests: reviewer conflict resolution protocol

load '../helpers/test-helpers'

AGENT_COMM="$PLUGIN_ROOT/shared/agent-communication.md"
QUALITY_GATE="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"

# ---------------------------------------------------------------------------
# 1. Conflict protocol section exists in agent-communication.md
# ---------------------------------------------------------------------------
@test "conflict-resolution: conflict reporting protocol section exists" {
  grep -q "### Conflict Reporting Protocol" "$AGENT_COMM" \
    || fail "Conflict Reporting Protocol section not found in agent-communication.md"
}

# ---------------------------------------------------------------------------
# 2. Priority ordering documented (security > architecture > ...)
# ---------------------------------------------------------------------------
@test "conflict-resolution: priority ordering documented with security first" {
  grep -q "Security.*SEC-\*" "$AGENT_COMM" \
    || fail "Security priority not documented"
  grep -q "Architecture.*ARCH-\*" "$AGENT_COMM" \
    || fail "Architecture priority not documented"

  # Verify security appears before architecture in priority ordering
  local sec_line arch_line
  sec_line=$(grep -n "Security.*SEC-\*" "$AGENT_COMM" | head -1 | cut -d: -f1)
  arch_line=$(grep -n "Architecture.*ARCH-\*" "$AGENT_COMM" | head -1 | cut -d: -f1)
  [[ "$sec_line" -lt "$arch_line" ]] \
    || fail "Security priority (line $sec_line) should come before Architecture (line $arch_line)"
}

# ---------------------------------------------------------------------------
# 3. Quality gate has conflict detection section
# ---------------------------------------------------------------------------
@test "conflict-resolution: quality gate has conflict detection section" {
  grep -q "## 6.1 Conflict Detection" "$QUALITY_GATE" \
    || fail "Conflict Detection section not found in fg-400-quality-gate.md"
}

# ---------------------------------------------------------------------------
# 4. CONFLICT format/marker documented
# ---------------------------------------------------------------------------
@test "conflict-resolution: CONFLICT format documented" {
  grep -q "CONFLICT:" "$AGENT_COMM" \
    || fail "CONFLICT marker not documented in agent-communication.md"
  grep -q "Agent A:" "$AGENT_COMM" \
    || fail "CONFLICT format Agent A line not documented"
  grep -q "Agent B:" "$AGENT_COMM" \
    || fail "CONFLICT format Agent B line not documented"
}

# ---------------------------------------------------------------------------
# 5. Quality gate resolves conflicts before scoring (section ordering)
# ---------------------------------------------------------------------------
@test "conflict-resolution: conflict detection comes before scoring in quality gate" {
  local conflict_line scoring_line
  conflict_line=$(grep -n "## 6.1 Conflict Detection" "$QUALITY_GATE" | head -1 | cut -d: -f1)
  scoring_line=$(grep -n "## 8. Scoring" "$QUALITY_GATE" | head -1 | cut -d: -f1)
  [[ "$conflict_line" -lt "$scoring_line" ]] \
    || fail "Conflict Detection (line $conflict_line) must come before Scoring (line $scoring_line)"
}
