#!/usr/bin/env bats
# AC-REVIEW-005, AC-REVIEW-006, AC-BEYOND-004: consistency promotion.
load '../helpers/test-helpers'

SYN="$PLUGIN_ROOT/tests/fixtures/phase-D/synthetic-findings.json"

@test "synthetic findings file exists" {
  assert [ -f "$SYN" ]
}

@test "fixture has 3 reviewers on shared key (auth/jwt:42)" {
  run python3 -c "
import json,sys
data=json.load(open(sys.argv[1]))
keys={}
for f in data:
    k=(f['component'], f['file'], f['line'], f['category'])
    keys.setdefault(k, set()).add(f['reviewer'])
counts={k: len(v) for k,v in keys.items()}
assert counts[('auth','src/auth/jwt.ts',42,'SEC-INJECTION-OVERRIDE')] == 3
assert counts[('ui','src/ui/Form.tsx',88,'QUAL-NAMING')] == 2
" "$SYN"
  assert_success
}

@test "consistency promotion is documented for threshold=3 default" {
  run grep -E 'default 3' "$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
  assert_success
}

@test "consistency promotion sets confidence_weight to 1.0" {
  run grep -F '1.0' "$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
  assert_success
}

@test "enabled: false short-circuits the promotion pass" {
  run grep -E 'enabled.*false.*short[ -]circuit|short[ -]circuit.*enabled.*false' \
    "$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
  assert_success
}
