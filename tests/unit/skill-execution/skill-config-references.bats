#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  SCHEMA="$BATS_TEST_DIRNAME/../../../shared/config-schema.json"
}

@test "skill-config-refs: config-schema.json exists" {
  assert [ -f "$SCHEMA" ]
}

@test "skill-config-refs: schema is valid JSON" {
  run python3 - "$SCHEMA" <<'PYEOF'
import json, sys
json.load(open(sys.argv[1]))
PYEOF
  assert_success
}

@test "skill-config-refs: schema covers components section" {
  run grep -q '"components"' "$SCHEMA"
  assert_success
}

@test "skill-config-refs: schema covers scoring section" {
  run grep -q '"scoring"' "$SCHEMA"
  assert_success
}
