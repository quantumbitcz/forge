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
  run python3 -c "
import json, sys, jsonschema
schema = json.load(open('$SCHEMAS/hook-failures.schema.json'))
for line in open('$FIXTURES/hook-failure-sample.jsonl'):
    jsonschema.validate(json.loads(line), schema)
"
  assert_success
}

@test "progress-status fixture validates (skip if jsonschema absent)" {
  has_jsonschema || skip "jsonschema not installed"
  run python3 -c "
import json, jsonschema
schema = json.load(open('$SCHEMAS/progress-status.schema.json'))
jsonschema.validate(json.load(open('$FIXTURES/progress-status-sample.json')), schema)
"
  assert_success
}

@test "run-history-trends fixture validates (skip if jsonschema absent)" {
  has_jsonschema || skip "jsonschema not installed"
  run python3 -c "
import json, jsonschema, os
base = '$SCHEMAS'
schema = json.load(open(os.path.join(base,'run-history-trends.schema.json')))
from jsonschema import RefResolver
resolver = RefResolver(base_uri='file://' + base + '/', referrer=schema)
jsonschema.validate(json.load(open('$FIXTURES/run-history-trends-sample.json')), schema, resolver=resolver)
"
  assert_success
}
