#!/usr/bin/env bats
# Contract tests: shared/state-schema.json — validates schema file and fixtures.

load '../helpers/test-helpers'

SCHEMA_FILE="$PLUGIN_ROOT/shared/state-schema.json"
FIXTURE_VALID="$PLUGIN_ROOT/tests/fixtures/state/v1.5.0-valid.json"
FIXTURE_MALFORMED="$PLUGIN_ROOT/tests/fixtures/state/v1.0.0-malformed.json"
STATE_INIT="$PLUGIN_ROOT/shared/forge-state.sh"

# ---------------------------------------------------------------------------
# 1. Schema file exists and is valid JSON
# ---------------------------------------------------------------------------

@test "state-schema-json: file exists" {
  [[ -f "$SCHEMA_FILE" ]]
}

@test "state-schema-json: is valid JSON" {
  python3 -c "import json; json.load(open('$SCHEMA_FILE'))"
}

@test "state-schema-json: is JSON Schema draft-07" {
  local schema_ref
  schema_ref=$(python3 -c "import json; print(json.load(open('$SCHEMA_FILE')).get('\$schema', ''))")
  [[ "$schema_ref" == *"draft-07"* ]]
}

# ---------------------------------------------------------------------------
# 2. Required fields present in schema
# ---------------------------------------------------------------------------

@test "state-schema-json: requires version _seq complete story_id story_state mode" {
  local required
  required=$(python3 -c "
import json
s = json.load(open('$SCHEMA_FILE'))
print(' '.join(s.get('required', [])))
")
  for field in version _seq complete story_id story_state mode; do
    [[ "$required" == *"$field"* ]] || fail "Field $field not in required list: $required"
  done
}

@test "state-schema-json: requires convergence recovery recovery_budget integrations cost score_history" {
  local required
  required=$(python3 -c "
import json
s = json.load(open('$SCHEMA_FILE'))
print(' '.join(s.get('required', [])))
")
  for field in convergence recovery recovery_budget integrations cost score_history; do
    [[ "$required" == *"$field"* ]] || fail "Field $field not in required list: $required"
  done
}

# ---------------------------------------------------------------------------
# 3. Enum constraints
# ---------------------------------------------------------------------------

@test "state-schema-json: story_state enum includes all pipeline states" {
  local states
  states=$(python3 -c "
import json
s = json.load(open('$SCHEMA_FILE'))
print(' '.join(s['properties']['story_state']['enum']))
")
  for state in PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING COMPLETE ABORTED ESCALATED DECOMPOSED; do
    [[ "$states" == *"$state"* ]] || fail "story_state enum missing $state"
  done
}

@test "state-schema-json: mode enum includes all 7 modes" {
  local modes
  modes=$(python3 -c "
import json
s = json.load(open('$SCHEMA_FILE'))
print(' '.join(s['properties']['mode']['enum']))
")
  for mode in standard bugfix migration bootstrap testing refactor performance; do
    [[ "$modes" == *"$mode"* ]] || fail "mode enum missing $mode"
  done
}

@test "state-schema-json: convergence.phase enum includes correctness perfection safety_gate" {
  local phases
  phases=$(python3 -c "
import json
s = json.load(open('$SCHEMA_FILE'))
conv = s['properties']['convergence']['properties']
print(' '.join(conv['phase']['enum']))
")
  for phase in correctness perfection safety_gate; do
    [[ "$phases" == *"$phase"* ]] || fail "convergence.phase enum missing $phase"
  done
}

@test "state-schema-json: convergence.convergence_state enum includes IMPROVING PLATEAUED REGRESSING" {
  local states
  states=$(python3 -c "
import json
s = json.load(open('$SCHEMA_FILE'))
conv = s['properties']['convergence']['properties']
print(' '.join(conv['convergence_state']['enum']))
")
  for st in IMPROVING PLATEAUED REGRESSING; do
    [[ "$states" == *"$st"* ]] || fail "convergence_state enum missing $st"
  done
}

# ---------------------------------------------------------------------------
# 4. v1.5.0 fixture validates against schema
# ---------------------------------------------------------------------------

@test "state-schema-json: v1.5.0 fixture validates against schema" {
  # Skip if jsonschema not installed
  python3 -c "import jsonschema" 2>/dev/null || skip "jsonschema not installed"

  python3 -c "
import json
from jsonschema import validate
with open('$SCHEMA_FILE') as f:
    schema = json.load(f)
with open('$FIXTURE_VALID') as f:
    state = json.load(f)
validate(instance=state, schema=schema)
print('OK')
"
}

# ---------------------------------------------------------------------------
# 5. Malformed fixture is rejected
# ---------------------------------------------------------------------------

@test "state-schema-json: malformed fixture is not valid JSON" {
  run python3 -c "import json; json.load(open('$FIXTURE_MALFORMED'))"
  assert_failure
}

# ---------------------------------------------------------------------------
# 6. Counter constraints (non-negative)
# ---------------------------------------------------------------------------

@test "state-schema-json: _seq has minimum 0" {
  local min
  min=$(python3 -c "
import json
s = json.load(open('$SCHEMA_FILE'))
print(s['properties']['_seq'].get('minimum', 'MISSING'))
")
  assert_equal "$min" "0"
}

@test "state-schema-json: total_retries has minimum 0" {
  local min
  min=$(python3 -c "
import json
s = json.load(open('$SCHEMA_FILE'))
print(s['properties']['total_retries'].get('minimum', 'MISSING'))
")
  assert_equal "$min" "0"
}
