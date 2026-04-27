#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  python3 -c "
import json, os
p = os.path.join(os.environ['FORGE_DIR'], 'state.json')
with open(p) as fh:
    st = json.load(fh)
st['cost']['ceiling_usd'] = 1.00
st['cost']['spent_usd'] = 0.70
st['cost']['remaining_usd'] = 0.30
with open(p, 'w') as fh:
    json.dump(st, fh, indent=2)
"
}

@test "aware_routing with remaining=0.30, premium est=0.078, trip=0.39 -> downgrade (AC-607)" {
  run python3 -c "
import sys
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
t, r = downgrade_tier(
    agent='fg-200-planner', resolved_tier='premium', remaining_usd=0.30,
    tier_estimates={'fast':0.016,'standard':0.047,'premium':0.078},
    conservatism_multiplier={'fast':1.0,'standard':1.0,'premium':1.0},
    pinned_agents=[], aware_routing=True,
)
print(f'{t}|{r}')
"
  assert_success
  assert_output "standard|downgrade_from_premium"
}

@test "pinned_agent stays on premium even when trip is crossed (AC-609)" {
  run python3 -c "
import sys
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
t, r = downgrade_tier(
    agent='fg-200-planner', resolved_tier='premium', remaining_usd=0.30,
    tier_estimates={'fast':0.016,'standard':0.047,'premium':0.078},
    conservatism_multiplier={'fast':1.0,'standard':1.0,'premium':1.0},
    pinned_agents=['fg-200-planner'], aware_routing=True,
)
print(f'{t}|{r}')
"
  assert_success
  assert_output "premium|agent_pinned"
}

@test "downgrade appended to state.cost.downgrades[] with (from, to, remaining_usd)" {
  # Simulate the orchestrator state mutation performed in Task 14 Step 2.
  python3 -c "
import json, os, sys
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
from datetime import datetime, timezone
p = os.path.join(os.environ['FORGE_DIR'], 'state.json')
with open(p) as fh:
    st = json.load(fh)
t, r = downgrade_tier(
    agent='fg-412-architecture-reviewer', resolved_tier='premium',
    remaining_usd=st['cost']['remaining_usd'],
    tier_estimates=st['cost']['tier_estimates_usd'],
    conservatism_multiplier=st['cost']['conservatism_multiplier'],
    pinned_agents=[], aware_routing=True,
)
if t != 'premium':
    st['cost']['downgrades'].append({
        'agent': 'fg-412-architecture-reviewer',
        'from': 'premium', 'to': t,
        'remaining_usd': st['cost']['remaining_usd'],
        'timestamp': datetime.now(timezone.utc).isoformat(),
    })
    st['cost']['downgrade_count'] = len(st['cost']['downgrades'])
with open(p, 'w') as fh:
    json.dump(st, fh, indent=2)
"
  run python3 -c "
import json, os
st = json.load(open(os.path.join(os.environ['FORGE_DIR'], 'state.json')))
d = st['cost']['downgrades'][0]
assert d['agent'] == 'fg-412-architecture-reviewer'
assert d['from'] == 'premium' and d['to'] == 'standard'
assert d['remaining_usd'] == 0.30
print('ok')
"
  assert_success
}
