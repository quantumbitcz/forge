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

@test "category-registry: all 21 categories from scoring.md present" {
  local categories=(ARCH SEC PERF FE-PERF TEST CONV DOC QUAL QUAL-ERR QUAL-COMPLEX APPROACH SCOUT A11Y DEP COMPAT CONTRACT STRUCT INFRA REVIEW-GAP DESIGN-TOKEN DESIGN-MOTION)
  for cat in "${categories[@]}"; do
    python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
assert '$cat' in data['categories'], f'Category $cat not found in registry'
" || fail "Category $cat not found in registry"
  done
}

@test "category-registry: exactly 21 categories defined" {
  local count
  count=$(python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
print(len(data['categories']))
")
  [[ "$count" -eq 21 ]] || fail "Expected 21 categories, found $count"
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
for cat_name in ['COMPAT']:
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

@test "category-registry: SEC has highest priority (1)" {
  python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
assert data['categories']['SEC'].get('priority') == 1
" || fail "SEC does not have priority 1"
}

@test "category-registry: all active categories have numeric priority" {
  python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
missing = []
for cat_name, cat_data in data['categories'].items():
    if cat_data.get('status') == 'reserved':
        continue
    p = cat_data.get('priority')
    if not isinstance(p, int):
        missing.append(f'{cat_name}: priority={p}')
if missing:
    for m in missing:
        print(m, file=sys.stderr)
    sys.exit(1)
" || fail "Some active categories missing numeric priority"
}

@test "category-registry: priority values are 1-6" {
  python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
out_of_range = []
for cat_name, cat_data in data['categories'].items():
    p = cat_data.get('priority')
    if p is not None and (p < 1 or p > 6):
        out_of_range.append(f'{cat_name}: priority={p}')
if out_of_range:
    for o in out_of_range:
        print(o, file=sys.stderr)
    sys.exit(1)
" || fail "Some priorities outside 1-6 range"
}

@test "category-registry: SEC < ARCH < QUAL priority ordering" {
  python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
cats = data['categories']
sec_p = cats['SEC']['priority']
arch_p = cats['ARCH']['priority']
qual_p = cats['QUAL']['priority']
assert sec_p < arch_p < qual_p, f'Order wrong: SEC={sec_p}, ARCH={arch_p}, QUAL={qual_p}'
" || fail "Priority ordering wrong"
}

@test "category-registry: agent-communication.md references registry for priorities" {
  grep -q "category-registry.json" "$PLUGIN_ROOT/shared/agent-communication.md" \
    || fail "agent-communication.md does not reference category-registry.json"
}

# ---------------------------------------------------------------------------
# Affinity validation (v1.17)
# ---------------------------------------------------------------------------

@test "category-registry: every category has an affinity field" {
  python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
missing = []
for cat_name, cat_data in data['categories'].items():
    if 'affinity' not in cat_data:
        missing.append(cat_name)
if missing:
    for m in missing:
        print(f'  {m}', file=sys.stderr)
    sys.exit(1)
" || fail "Some categories missing affinity field"
}

@test "category-registry: affinity values are JSON arrays" {
  python3 -c "
import json, sys
with open('$REGISTRY') as f:
    data = json.load(f)
bad = []
for cat_name, cat_data in data['categories'].items():
    aff = cat_data.get('affinity')
    if not isinstance(aff, list):
        bad.append(f'{cat_name}: type={type(aff).__name__}')
if bad:
    for b in bad:
        print(f'  {b}', file=sys.stderr)
    sys.exit(1)
" || fail "Some affinity values are not arrays"
}

@test "category-registry: affinity agent IDs match known agents from agent-registry.md" {
  python3 -c "
import json, os, sys

# Parse known agent IDs from agent-registry.md
registry_md = os.path.join('$PLUGIN_ROOT', 'shared', 'agent-registry.md')
known_ids = set()
with open(registry_md) as f:
    for line in f:
        line = line.strip()
        if line.startswith('| fg-'):
            agent_id = line.split('|')[1].strip()
            known_ids.add(agent_id)

# Validate affinity references
with open('$REGISTRY') as f:
    data = json.load(f)
unknown = []
for cat_name, cat_data in data['categories'].items():
    for agent in cat_data.get('affinity', []):
        if agent not in known_ids:
            unknown.append(f'{cat_name}: {agent}')
if unknown:
    for u in unknown:
        print(f'  {u}', file=sys.stderr)
    sys.exit(1)
" || fail "Some affinity agent IDs not found in agent-registry.md"
}

@test "category-registry: QUAL-ERR subcategory exists" {
  python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
assert 'QUAL-ERR' in data['categories'], 'QUAL-ERR not found in registry'
" || fail "QUAL-ERR subcategory missing from category registry"
}

@test "category-registry: QUAL-COMPLEX subcategory exists" {
  python3 -c "
import json
with open('$REGISTRY') as f:
    data = json.load(f)
assert 'QUAL-COMPLEX' in data['categories'], 'QUAL-COMPLEX not found in registry'
" || fail "QUAL-COMPLEX subcategory missing from category registry"
}
