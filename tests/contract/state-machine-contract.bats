#!/usr/bin/env bats
# Contract tests: forge-state.sh <-> state-transitions.md consistency.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state.sh"
TRANSITIONS="$PLUGIN_ROOT/shared/state-transitions.md"
TRANSITIONS_PY="$PLUGIN_ROOT/shared/python/state_transitions.py"

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
  events=$(python3 - "$TRANSITIONS" <<'PYEOF'
import re, sys
with open(sys.argv[1]) as f:
    content = f.read()
# Match events in the table (backtick-wrapped values in 3rd column).
# The Normal Flow table is the only one whose third column holds an event
# identifier; mode-specific config tables also use the | N | x | y | shape
# but their third column is a config key like ``max_quality_cycles``. We
# filter out pure-numeric matches (which only appear as column values in
# those config tables) so the assertion stays scoped to event names.
events = set()
for line in content.split('\n'):
    m = re.match(r'^\|\s*\w+\s*\|\s*\S+\s*\|\s*\x60?(\w+)\x60?\s*\|', line)
    if m:
        events.add(m.group(1))
# Remove header words and pure-numeric spurious matches.
events -= {'event', 'guard', 'current_state'}
events = {e for e in events if not e.isdigit()}
for e in sorted(events):
    print(e)
PYEOF
  )

  # Transitions are implemented in state_transitions.py (extracted from forge-state.sh in v2.7.0)
  for event in $events; do
    grep -q "'$event'" "$TRANSITIONS_PY" || grep -q "\"$event\"" "$TRANSITIONS_PY" || fail "Event '$event' from state-transitions.md not found in state_transitions.py"
  done
}

@test "state-machine-contract: all error events (E1-E7) exist in state_transitions.py" {
  for event in budget_exhausted recovery_budget_exhausted circuit_breaker_open unrecoverable_error user_continue user_abort user_reshape; do
    grep -q "'$event'" "$TRANSITIONS_PY" || grep -q "\"$event\"" "$TRANSITIONS_PY" || fail "Error event '$event' not in state_transitions.py"
  done
}

@test "state-machine-contract: token_budget_exhausted (E8) exists in state_transitions.py" {
  grep -q "token_budget_exhausted" "$TRANSITIONS_PY" || fail "E8 token_budget_exhausted not in state_transitions.py"
}

@test "state-machine-contract: score_diminishing (row 50) exists in state_transitions.py" {
  grep -q "score_diminishing" "$TRANSITIONS_PY" || fail "Row 50 score_diminishing not in state_transitions.py"
}

@test "state-machine-contract: validate_complete dry-run (D1) exists in state_transitions.py" {
  grep -q "validate_complete" "$TRANSITIONS_PY" || fail "D1 validate_complete not in state_transitions.py"
}

@test "state-machine-contract: all pipeline states from transitions table exist in state_transitions.py" {
  for state in PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING COMPLETE ESCALATED ABORTED DECOMPOSED; do
    grep -q "'$state'" "$TRANSITIONS_PY" || grep -q "\"$state\"" "$TRANSITIONS_PY" || fail "State '$state' not in state_transitions.py"
  done
}
