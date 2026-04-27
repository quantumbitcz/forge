#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  # Budget nearly exhausted; every safety-critical agent at fast tier.
  python3 -c "
import json, os
from pathlib import Path
p = Path(os.environ['FORGE_DIR']) / 'state.json'
with open(p) as fh:
    st = json.load(fh)
st['cost']['ceiling_usd'] = 0.05
st['cost']['spent_usd'] = 0.049
st['cost']['remaining_usd'] = 0.001
with open(p, 'w') as fh:
    json.dump(st, fh, indent=2)
"
}

@test "fg-411-security-reviewer at fast: NEVER silently dropped" {
  # Precondition: this test hardcodes fg-411-security-reviewer. If the agent
  # name changes or it's removed from SAFETY_CRITICAL, the test would silently
  # route through the wrong branch. Fail fast instead.
  python3 -c "
import sys
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import is_safety_critical
assert is_safety_critical('fg-411-security-reviewer'), 'fg-411-security-reviewer must be SAFETY_CRITICAL'
"
  # In interactive mode, orchestrator must escalate (not skip).
  python3 -c "
import json, os
from pathlib import Path
p = Path(os.environ['FORGE_DIR']) / 'state.json'
with open(p) as fh:
    st = json.load(fh)
st['autonomous'] = False
with open(p, 'w') as fh:
    json.dump(st, fh, indent=2)
"
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-411-security-reviewer fast
  assert_success
  assert_output -p '"action": "ask-user"'
  refute_output -p '"action": "skip"'
}

@test "fg-411-security-reviewer at fast + autonomous: abort_to_ship, NEVER skip" {
  # Precondition: see preceding test — guard against silent membership drift.
  python3 -c "
import sys
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import is_safety_critical
assert is_safety_critical('fg-411-security-reviewer'), 'fg-411-security-reviewer must be SAFETY_CRITICAL'
"
  python3 -c "
import json, os
from pathlib import Path
p = Path(os.environ['FORGE_DIR']) / 'state.json'
with open(p) as fh:
    st = json.load(fh)
st['autonomous'] = True
with open(p, 'w') as fh:
    json.dump(st, fh, indent=2)
"
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-411-security-reviewer fast
  assert_success
  assert_output -p '"decision": "abort_to_ship"'
  refute_output -p 'skip'
}

@test "every SAFETY_CRITICAL agent declared in cost_governance is a known agent" {
  run python3 -c "
import os, sys, pathlib
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import SAFETY_CRITICAL
agents_dir = pathlib.Path('$PLUGIN_ROOT/agents')
for a in SAFETY_CRITICAL:
    assert (agents_dir / f'{a}.md').exists(), f'missing agent file: {a}'
print('ok')
"
  assert_success
}

# NOTE: SAFETY_CRITICAL membership and count are canonically asserted in
# tests/unit/cost-governance-helpers.bats. The scenarios above rely on
# fg-411-security-reviewer being a member; the precondition guards in each
# test fail fast if membership drifts, so a count assertion here would be
# redundant.
