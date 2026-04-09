#!/usr/bin/env bats
# Contract tests: forge-state.sh <-> state-transitions.md consistency.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state.sh"
TRANSITIONS="$PLUGIN_ROOT/shared/state-transitions.md"

@test "state-machine-contract: forge-state.sh exists" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "state-machine-contract: state-transitions.md exists" {
  assert [ -f "$TRANSITIONS" ]
}

@test "state-machine-contract: all normal flow events from transitions table exist in forge-state.sh" {
  # Extract unique events from the Normal Flow table
  local events
  events=$(python3 -c "
import re
with open('$TRANSITIONS') as f:
    content = f.read()
# Match events in the table (backtick-wrapped values in 3rd column)
events = set()
for line in content.split('\n'):
    # Match table rows: | N | STATE | event | ...
    m = re.match(r'^\|\s*\w+\s*\|\s*\S+\s*\|\s*\x60?(\w+)\x60?\s*\|', line)
    if m:
        events.add(m.group(1))
# Remove header words
events -= {'event', 'guard', 'current_state'}
for e in sorted(events):
    print(e)
")

  for event in $events; do
    grep -q "'$event'" "$SCRIPT" || grep -q "\"$event\"" "$SCRIPT" || fail "Event '$event' from state-transitions.md not found in forge-state.sh"
  done
}

@test "state-machine-contract: all error events (E1-E7) exist in forge-state.sh" {
  for event in budget_exhausted recovery_budget_exhausted circuit_breaker_open unrecoverable_error user_continue user_abort user_reshape; do
    grep -q "'$event'" "$SCRIPT" || grep -q "\"$event\"" "$SCRIPT" || fail "Error event '$event' not in forge-state.sh"
  done
}

@test "state-machine-contract: token_budget_exhausted (E8) exists in forge-state.sh" {
  grep -q "token_budget_exhausted" "$SCRIPT" || fail "E8 token_budget_exhausted not in forge-state.sh"
}

@test "state-machine-contract: score_diminishing (row 50) exists in forge-state.sh" {
  grep -q "score_diminishing" "$SCRIPT" || fail "Row 50 score_diminishing not in forge-state.sh"
}

@test "state-machine-contract: validate_complete dry-run (D1) exists in forge-state.sh" {
  grep -q "validate_complete" "$SCRIPT" || fail "D1 validate_complete not in forge-state.sh"
}

@test "state-machine-contract: all pipeline states from transitions table exist in forge-state.sh" {
  for state in PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING COMPLETE ESCALATED ABORTED DECOMPOSED; do
    grep -q "'$state'" "$SCRIPT" || grep -q "\"$state\"" "$SCRIPT" || fail "State '$state' not in forge-state.sh"
  done
}
