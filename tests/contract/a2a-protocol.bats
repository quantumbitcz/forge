#!/usr/bin/env bats
# Contract tests: A2A protocol — validates shared/a2a-protocol.md structure and required sections.

load '../helpers/test-helpers'

A2A_PROTOCOL="$PLUGIN_ROOT/shared/a2a-protocol.md"

# ---------------------------------------------------------------------------
# 1. File exists
# ---------------------------------------------------------------------------
@test "a2a-protocol: shared/a2a-protocol.md exists" {
  [[ -f "$A2A_PROTOCOL" ]]
}

# ---------------------------------------------------------------------------
# 2. Task Lifecycle Mapping section present
# ---------------------------------------------------------------------------
@test "a2a-protocol: contains Task Lifecycle Mapping section" {
  grep -q "Task Lifecycle Mapping" "$A2A_PROTOCOL" \
    || fail "Task Lifecycle Mapping section not found"
}

# ---------------------------------------------------------------------------
# 3. Agent Card Schema section present
# ---------------------------------------------------------------------------
@test "a2a-protocol: contains Agent Card Schema section" {
  grep -q "Agent Card Schema" "$A2A_PROTOCOL" \
    || fail "Agent Card Schema section not found"
}

# ---------------------------------------------------------------------------
# 4. Fallback Behavior section present
# ---------------------------------------------------------------------------
@test "a2a-protocol: contains Fallback Behavior section" {
  grep -q "Fallback Behavior" "$A2A_PROTOCOL" \
    || fail "Fallback Behavior section not found"
}

# ---------------------------------------------------------------------------
# 5. All A2A task states documented in lifecycle mapping
# ---------------------------------------------------------------------------
@test "a2a-protocol: all A2A task states documented" {
  for state in pending in-progress input-required completed failed; do
    grep -q "$state" "$A2A_PROTOCOL" \
      || fail "A2A task state '$state' not documented"
  done
}

# ---------------------------------------------------------------------------
# 6. Agent card schema references agent-card.json
# ---------------------------------------------------------------------------
@test "a2a-protocol: references agent-card.json file" {
  grep -q "agent-card\.json" "$A2A_PROTOCOL" \
    || fail "agent-card.json not referenced in A2A protocol"
}

# ---------------------------------------------------------------------------
# 7. Agent card generation documents forge-init as creator
# ---------------------------------------------------------------------------
@test "a2a-protocol: forge-init creates agent card" {
  grep -q "forge-init" "$A2A_PROTOCOL" \
    || fail "forge-init not mentioned as agent card creator"
}

# ---------------------------------------------------------------------------
# 8. Cross-repo coordination references fg-103
# ---------------------------------------------------------------------------
@test "a2a-protocol: fg-103 reads agent cards" {
  grep -q "fg-103" "$A2A_PROTOCOL" \
    || fail "fg-103 not mentioned as agent card consumer"
}

# ---------------------------------------------------------------------------
# 9. Local adaptation documents filesystem-based transport
# ---------------------------------------------------------------------------
@test "a2a-protocol: documents filesystem-based transport" {
  grep -qi "filesystem" "$A2A_PROTOCOL" \
    || fail "Filesystem-based transport not documented"
}

# ---------------------------------------------------------------------------
# 10. Configuration documents implicit activation
# ---------------------------------------------------------------------------
@test "a2a-protocol: documents implicit configuration" {
  grep -qi "implicit\|no.*explicit.*config\|presence.*signal" "$A2A_PROTOCOL" \
    || fail "Implicit configuration not documented"
}
