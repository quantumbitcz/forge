#!/usr/bin/env bats
# Contract: phase-1 JSON schemas validate against fixtures.
load '../helpers/test-helpers'

setup() {
  SCHEMAS="$PLUGIN_ROOT/shared/schemas"
  FIXTURES="$PLUGIN_ROOT/tests/fixtures/phase1"
}

has_jsonschema() {
  python3 -c 'import jsonschema' 2>/dev/null
}

@test "hook-failures schema file exists" {
  assert [ -f "$SCHEMAS/hook-failures.schema.json" ]
}

@test "progress-status schema file exists" {
  assert [ -f "$SCHEMAS/progress-status.schema.json" ]
}

@test "run-history-trends schema file exists" {
  assert [ -f "$SCHEMAS/run-history-trends.schema.json" ]
}

@test "hook-failures fixture validates (skip if jsonschema absent)" {
  has_jsonschema || skip "jsonschema not installed"
  run python3 - "$SCHEMAS/hook-failures.schema.json" "$FIXTURES/hook-failure-sample.jsonl" <<'PYEOF'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
for line in open(sys.argv[2]):
    jsonschema.validate(json.loads(line), schema)
PYEOF
  assert_success
}

@test "progress-status fixture validates (skip if jsonschema absent)" {
  has_jsonschema || skip "jsonschema not installed"
  run python3 - "$SCHEMAS/progress-status.schema.json" "$FIXTURES/progress-status-sample.json" <<'PYEOF'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
jsonschema.validate(json.load(open(sys.argv[2])), schema)
PYEOF
  assert_success
}

@test "run-history-trends fixture validates (skip if jsonschema absent)" {
  has_jsonschema || skip "jsonschema not installed"
  run python3 - "$SCHEMAS" "$FIXTURES/run-history-trends-sample.json" <<'PYEOF'
import json, sys, jsonschema, os
base = sys.argv[1]
schema = json.load(open(os.path.join(base,'run-history-trends.schema.json')))
hook_schema = json.load(open(os.path.join(base,'hook-failures.schema.json')))
from jsonschema import RefResolver
# Both schemas declare absolute $id URLs; the run-history-trends schema also
# uses a relative $ref ('hook-failures.schema.json'). RefResolver needs both
# the absolute $id and the relative reference in its store, otherwise it
# falls through to remote HTTP fetch (which fails offline).
store = {
    schema.get('$id', ''): schema,
    hook_schema.get('$id', ''): hook_schema,
    'hook-failures.schema.json': hook_schema,
}
resolver = RefResolver(base_uri='file://' + base + '/', referrer=schema, store=store)
jsonschema.validate(json.load(open(sys.argv[2])), schema, resolver=resolver)
PYEOF
  assert_success
}
