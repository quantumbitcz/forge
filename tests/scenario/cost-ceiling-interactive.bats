#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  # Seed: spent 0.48 of 0.50 ceiling; planner tier_estimate = 0.078.
  python3 -c "
import json, os
p = os.path.join(os.environ['FORGE_DIR'], 'state.json')
with open(p) as fh:
    st = json.load(fh)
st['cost']['ceiling_usd'] = 0.50
st['cost']['spent_usd'] = 0.48
st['cost']['remaining_usd'] = 0.02
st['autonomous'] = False
with open(p, 'w') as fh:
    json.dump(st, fh, indent=2)
"
}

@test "interactive breach: AskUserQuestion payload matches §8 pattern" {
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium
  assert_success
  assert_output -p '"action": "ask-user"'
  assert_output -p '"header": "Cost ceiling"'
  assert_output -p '"question": "Next dispatch would breach cost ceiling'
  assert_output -p 'Downgrade remaining agents (Recommended)'
  assert_output -p 'Abort to ship current state'
  assert_output -p 'Abort fully'
}

@test "interactive breach: header is exactly 12 chars" {
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium
  assert_success
  run python3 -c "
import json, sys
d = json.loads('''$output''')
print(len(d['payload']['header']))
"
  assert_output "12"
}

@test "interactive breach: ceiling_breaches counter incremented to 1" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  run python3 -c "
import json, os
st = json.load(open(os.path.join(os.environ['FORGE_DIR'], 'state.json')))
print(st['cost']['ceiling_breaches'])
"
  assert_output "1"
}

@test "interactive breach: .forge/cost-incidents/*.json written" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  run bash -c "ls $FORGE_DIR/cost-incidents/*.json | wc -l"
  assert_output "1"
}
