#!/usr/bin/env bats
# Contract tests: shared/agent-communication.md — validates the communication protocol.

load '../helpers/test-helpers'

AGENT_COMM="$PLUGIN_ROOT/shared/agent-communication.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "agent-communication: document exists" {
  [[ -f "$AGENT_COMM" ]]
}

# ---------------------------------------------------------------------------
# 2. Stage notes section with format and lifetime
# ---------------------------------------------------------------------------
@test "agent-communication: stage notes section documented" {
  grep -q "Stage Notes" "$AGENT_COMM" \
    || fail "Stage Notes section not found"
  grep -q "stage_N_notes" "$AGENT_COMM" \
    || fail "stage_N_notes naming convention not documented"
}

# ---------------------------------------------------------------------------
# 3. What goes in and what does NOT go in stage notes
# ---------------------------------------------------------------------------
@test "agent-communication: stage notes content rules documented" {
  grep -q "What goes in stage notes" "$AGENT_COMM" \
    || fail "What goes in stage notes section not found"
  grep -q "What does NOT go in stage notes" "$AGENT_COMM" \
    || fail "What does NOT go in stage notes section not found"
}

# ---------------------------------------------------------------------------
# 4. Stage notes size budget (2,000 tokens)
# ---------------------------------------------------------------------------
@test "agent-communication: 2000 token stage notes budget documented" {
  grep -q "2,000 tokens" "$AGENT_COMM" \
    || fail "2,000 token stage notes budget not documented"
}

# ---------------------------------------------------------------------------
# 5. Orchestrator is sole state writer
# ---------------------------------------------------------------------------
@test "agent-communication: orchestrator is sole writer of state.json" {
  grep -qi "orchestrator.*sole writer\|sole writer.*state.json\|never write.*state" "$AGENT_COMM" \
    || fail "Orchestrator sole state writer rule not documented"
}

# ---------------------------------------------------------------------------
# 6. Data flow summary section exists
# ---------------------------------------------------------------------------
@test "agent-communication: data flow summary section exists" {
  grep -q "Data Flow Summary" "$AGENT_COMM" \
    || fail "Data Flow Summary section not found"
}

# ---------------------------------------------------------------------------
# 7. PREEMPT item tracking documented
# ---------------------------------------------------------------------------
@test "agent-communication: PREEMPT item tracking documented" {
  grep -q "PREEMPT_APPLIED" "$AGENT_COMM" \
    || fail "PREEMPT_APPLIED marker not documented"
  grep -q "PREEMPT_SKIPPED" "$AGENT_COMM" \
    || fail "PREEMPT_SKIPPED marker not documented"
}

# ---------------------------------------------------------------------------
# 8. Conditional agents table exists
# ---------------------------------------------------------------------------
@test "agent-communication: conditional agents table documented" {
  grep -q "Conditional Agents" "$AGENT_COMM" \
    || fail "Conditional Agents section not found"
  grep -q "fg-320-frontend-polisher" "$AGENT_COMM" \
    || fail "fg-320-frontend-polisher not listed in conditional agents"
}

# ---------------------------------------------------------------------------
# 9. Convention file composition documented
# ---------------------------------------------------------------------------
@test "agent-communication: convention file composition documented" {
  grep -qi "convention.*composition\|convention.*stack\|convention.*layers" "$AGENT_COMM" \
    || fail "Convention file composition not documented"
}
