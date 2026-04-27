#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  python3 -c "
import json, os
from pathlib import Path
p = Path(os.environ['FORGE_DIR']) / 'state.json'
with open(p) as fh:
    st = json.load(fh)
st['cost']['ceiling_usd'] = 0
st['cost']['spent_usd'] = 9999.99
with open(p, 'w') as fh:
    json.dump(st, fh, indent=2)
"
}

@test "ceiling_usd=0: no incident written even at huge spend" {
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium
  assert_success
  assert_output -p '"action": "dispatch"'
  run bash -c "ls $FORGE_DIR/cost-incidents/ 2>/dev/null | wc -l"
  assert_output "0"
}

@test "ceiling_usd=0: budget block renders 'unlimited'" {
  run python3 -c "
import sys
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import compute_budget_block
out = compute_budget_block(ceiling_usd=0, spent_usd=123.45, tier='premium', tier_estimate=0.078)
assert 'unlimited' in out.lower()
print(out)
"
  assert_success
  assert_output -p "unlimited"
  assert_output -p 'Your tier: premium'
}
