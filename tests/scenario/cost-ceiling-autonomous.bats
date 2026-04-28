#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  export PLUGIN_ROOT
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
  python3 - "$FORGE_DIR/state.json" <<'PY'
import json
import sys
from pathlib import Path

p = Path(sys.argv[1])
with p.open() as fh:
    st = json.load(fh)
st['cost']['ceiling_usd'] = 0.50
st['cost']['spent_usd'] = 0.48
st['cost']['remaining_usd'] = 0.02
st['autonomous'] = True
with p.open('w') as fh:
    json.dump(st, fh, indent=2)
PY
}

@test "autonomous breach: auto-decides downgrade (AC-604)" {
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium
  assert_success
  assert_output -p '"action": "auto-decide"'
  assert_output -p '"decision": "downgrade"'
  assert_output -p '"from": "premium"'
  assert_output -p '"to": "standard"'
  refute_output -p 'ask-user'
}

@test "autonomous breach at fast tier: auto-decides abort_to_ship" {
  # Per-test override: shared setup leaves projected ≤ ceiling at fast tier
  # (spent=0.48 + 0.016 = 0.496 ≤ 0.50). Bump spent so the breach branch fires.
  python3 - "$FORGE_DIR/state.json" <<'PY'
import json
import sys
from pathlib import Path

p = Path(sys.argv[1])
with p.open() as fh:
    st = json.load(fh)
st['cost']['spent_usd'] = 0.495
st['cost']['remaining_usd'] = 0.005
with p.open('w') as fh:
    json.dump(st, fh, indent=2)
PY
  run python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-410-code-reviewer fast
  assert_success
  assert_output -p '"decision": "abort_to_ship"'
  refute_output -p 'ask-user'
}

@test "autonomous breach: incident.autonomous == true" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  local incident
  incident=$(ls "$FORGE_DIR/cost-incidents/"*.json | head -1)
  run python3 - "$incident" <<'PY'
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as fh:
    print(json.load(fh)['autonomous'])
PY
  assert_output "True"
}
