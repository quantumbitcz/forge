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
st['cost']['spent_usd'] = 0.49
st['cost']['remaining_usd'] = 0.01
st['autonomous'] = True
with p.open('w') as fh:
    json.dump(st, fh, indent=2)
PY
}

@test "incident file written with all required keys" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  local incident
  incident=$(ls "$FORGE_DIR/cost-incidents/"*.json | head -1)
  run python3 - "$incident" <<'PY'
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as fh:
    d = json.load(fh)
for k in ['timestamp', 'ceiling_usd', 'spent_usd', 'projected_usd', 'next_agent',
         'resolved_tier', 'decision', 'autonomous', 'run_id']:
    assert k in d, f'missing {k}'
print('ok')
PY
  assert_success
}

@test "incident file validates against cost-incident.schema.json" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  local incident
  incident=$(ls "$FORGE_DIR/cost-incidents/"*.json | head -1)
  run python3 - "$PLUGIN_ROOT/shared/schemas/cost-incident.schema.json" "$incident" <<'PY'
import json
import sys
from pathlib import Path

try:
    import jsonschema
except ImportError:
    # CI installs jsonschema via pyproject test extras (Step 2 above).
    # Local dev may not; skip gracefully to avoid false red locally.
    print('SKIP: jsonschema not installed')
    sys.exit(0)
with Path(sys.argv[1]).open() as fh:
    schema = json.load(fh)
with Path(sys.argv[2]).open() as fh:
    incident = json.load(fh)
jsonschema.validate(incident, schema)
print('ok')
PY
  assert_success
}

@test "incident.next_agent matches agent-ID pattern fg-NNN-name" {
  python3 "$PLUGIN_ROOT/tests/helpers/orchestrator-gate-sim.py" fg-200-planner premium >/dev/null
  local incident
  incident=$(ls "$FORGE_DIR/cost-incidents/"*.json | head -1)
  run python3 - "$incident" <<'PY'
import json
import re
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as fh:
    d = json.load(fh)
assert re.match(r'^fg-[0-9]{3}-[a-z-]+$', d['next_agent']), d['next_agent']
print('ok')
PY
  assert_success
}
