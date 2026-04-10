#!/usr/bin/env bats
# Contract tests: category-registry.json — canonical finding category registry.

load '../helpers/test-helpers'

REGISTRY="$PLUGIN_ROOT/shared/checks/category-registry.json"
SCORING="$PLUGIN_ROOT/shared/scoring.md"

@test "category-registry: file exists" {
  [[ -f "$REGISTRY" ]] || fail "shared/checks/category-registry.json does not exist"
}

@test "category-registry: file is valid JSON" {
  run python3 -m json.tool "$REGISTRY"
  assert_success
}

@test "category-registry: all 19 categories from scoring.md present" {
  local categories=(ARCH SEC PERF FE-PERF TEST CONV DOC QUAL APPROACH SCOUT A11Y DEPS COMPAT CONTRACT STRUCT INFRA REVIEW-GAP DESIGN-TOKEN DESIGN-MOTION)
  for cat in "${categories[@]}"; do
    python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
assert '$cat' in data['categories'], f'Category $cat not found in registry'
" || fail "Category $cat not found in registry"
  done
}

@test "category-registry: exactly 19 categories defined" {
  local count
  count=$(python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
print(len(data['categories']))
")
  [[ "$count" -eq 19 ]] || fail "Expected 19 categories, found $count"
}

@test "category-registry: all agent references exist as files" {
  python3 -c "
import json, os, sys
with open('$REGISTRY') as f:
    data = json.load(f)
missing = []
for cat_name, cat_data in data['categories'].items():
    for agent in cat_data.get('agents', []):
        agent_file = os.path.join('$PLUGIN_ROOT', 'agents', agent + '.md')
        if not os.path.isfile(agent_file):
            missing.append(f'{cat_name}: {agent}')
if missing:
    for m in missing:
        print(f'  {m}', file=sys.stderr)
    sys.exit(1)
" || fail "Some agent references do not map to existing files"
}

@test "category-registry: SCOUT has score_impact NONE" {
  python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
scout = data['categories']['SCOUT']
assert scout.get('score_impact') == 'NONE', f'SCOUT score_impact: {scout.get(\"score_impact\")}'
" || fail "SCOUT does not have score_impact: NONE"
}

@test "category-registry: reserved categories have empty agent list" {
  python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
for cat_name in ['DEPS', 'COMPAT']:
    cat = data['categories'][cat_name]
    assert cat.get('status') == 'reserved', f'{cat_name} status: {cat.get(\"status\")}'
    assert cat.get('agents') == [], f'{cat_name} agents: {cat.get(\"agents\")}'
" || fail "Reserved categories not properly configured"
}

@test "category-registry: each category has description, agents, wildcard" {
  python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
errors = []
for cat_name, cat_data in data['categories'].items():
    for field in ['description', 'agents', 'wildcard']:
        if field not in cat_data:
            errors.append(f'{cat_name} missing field: {field}')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
" || fail "Some categories missing required fields"
}
