#!/usr/bin/env bash
# Helpers for cost-soft-throttle scenario tests. Loaded via:
#   load '../helpers/implementer-harness'
# Exposes:
#   seed_state_cost_pct <fraction>  — mutate $FORGE_DIR/state.json cost block
#   implementer_harness <subcmd> <task_id> — read-only dispatch simulator

# Seed state.cost to a target pct_consumed value.
seed_state_cost_pct() {
  local target_pct="$1"
  python3 -c "
import json, os
p = os.path.join(os.environ['FORGE_DIR'], 'state.json')
with open(p) as fh:
    st = json.load(fh)
ceiling = float(st['cost']['ceiling_usd'])
spent = ceiling * float('$target_pct')
st['cost']['spent_usd'] = round(spent, 4)
st['cost']['remaining_usd'] = round(max(0.0, ceiling - spent), 4)
st['cost']['pct_consumed'] = round(spent / ceiling, 4) if ceiling > 0 else 0.0
with open(p, 'w') as fh:
    json.dump(st, fh, indent=2)
"
}

# Read-only dispatch simulator. Echoes the same log lines the real implementer
# would emit, so scenario assertions can pattern-match without a live subagent.
implementer_harness() {
  python3 "$PLUGIN_ROOT/tests/helpers/implementer_sim.py" "$@"
}
