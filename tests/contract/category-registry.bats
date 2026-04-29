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
    python3 - "$REGISTRY" "$cat" <<'PYEOF' || fail "Category $cat not found in registry"
import json, sys
registry, cat = sys.argv[1], sys.argv[2]
with open(registry) as f:
    data = json.load(f)
assert cat in data['categories'], f'Category {cat} not found in registry'
PYEOF
  done
}

@test "category-registry: at least 21 categories defined" {
  local count
  count=$(python3 - "$REGISTRY" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(len(data['categories']))
PYEOF
)
  [[ "$count" -ge 21 ]] || fail "Expected at least 21 categories, found $count"
}

@test "category-registry: all agent references exist as files" {
  python3 - "$REGISTRY" "$PLUGIN_ROOT" <<'PYEOF' || fail "Some agent references do not map to existing files"
import json, os, sys
registry, plugin_root = sys.argv[1], sys.argv[2]
with open(registry) as f:
    data = json.load(f)
missing = []
for cat_name, cat_data in data['categories'].items():
    for agent in cat_data.get('agents', []):
        agent_file = os.path.join(plugin_root, 'agents', agent + '.md')
        if not os.path.isfile(agent_file):
            missing.append(f'{cat_name}: {agent}')
if missing:
    for m in missing:
        print(f'  {m}', file=sys.stderr)
    sys.exit(1)
PYEOF
}

@test "category-registry: SCOUT has score_impact NONE" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "SCOUT does not have score_impact: NONE"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
scout = data['categories']['SCOUT']
assert scout.get('score_impact') == 'NONE', f"SCOUT score_impact: {scout.get('score_impact')}"
PYEOF
}

@test "category-registry: reserved categories have empty agent list" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "Reserved categories not properly configured"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for cat_name in ['COMPAT']:
    cat = data['categories'][cat_name]
    assert cat.get('status') == 'reserved', f"{cat_name} status: {cat.get('status')}"
    assert cat.get('agents') == [], f"{cat_name} agents: {cat.get('agents')}"
PYEOF
}

@test "category-registry: each category has description, agents, wildcard" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "Some categories missing required fields"
import json, sys
with open(sys.argv[1]) as f:
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
PYEOF
}

@test "category-registry: SEC has highest priority (1)" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "SEC does not have priority 1"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
assert data['categories']['SEC'].get('priority') == 1
PYEOF
}

@test "category-registry: all active categories have numeric priority" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "Some active categories missing numeric priority"
import json, sys
with open(sys.argv[1]) as f:
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
PYEOF
}

@test "category-registry: priority values are 1-6" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "Some priorities outside 1-6 range"
import json, sys
with open(sys.argv[1]) as f:
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
PYEOF
}

@test "category-registry: SEC < ARCH < QUAL priority ordering" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "Priority ordering wrong"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
cats = data['categories']
sec_p = cats['SEC']['priority']
arch_p = cats['ARCH']['priority']
qual_p = cats['QUAL']['priority']
assert sec_p < arch_p < qual_p, f'Order wrong: SEC={sec_p}, ARCH={arch_p}, QUAL={qual_p}'
PYEOF
}

@test "category-registry: agent-communication.md references registry for priorities" {
  grep -q "category-registry.json" "$PLUGIN_ROOT/shared/agent-communication.md" \
    || fail "agent-communication.md does not reference category-registry.json"
}

# ---------------------------------------------------------------------------
# Affinity validation (v1.17)
# ---------------------------------------------------------------------------

@test "category-registry: every category has an affinity field" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "Some categories missing affinity field"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
missing = []
for cat_name, cat_data in data['categories'].items():
    if 'affinity' not in cat_data:
        missing.append(cat_name)
if missing:
    for m in missing:
        print(f'  {m}', file=sys.stderr)
    sys.exit(1)
PYEOF
}

@test "category-registry: affinity values are JSON arrays" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "Some affinity values are not arrays"
import json, sys
with open(sys.argv[1]) as f:
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
PYEOF
}

@test "category-registry: affinity agent IDs match known agents from agents.md" {
  python3 - "$REGISTRY" "$PLUGIN_ROOT" <<'PYEOF' || fail "Some affinity agent IDs not found in agents.md Registry"
import json, os, sys

registry, plugin_root = sys.argv[1], sys.argv[2]

# Parse known agent IDs from shared/agents.md (Registry section)
registry_md = os.path.join(plugin_root, 'shared', 'agents.md')
known_ids = set()
with open(registry_md) as f:
    for line in f:
        line = line.strip()
        if line.startswith('| fg-'):
            agent_id = line.split('|')[1].strip()
            known_ids.add(agent_id)

# Validate affinity references
with open(registry) as f:
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
PYEOF
}

@test "category-registry: QUAL-ERR subcategory exists" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "QUAL-ERR subcategory missing from category registry"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
assert 'QUAL-ERR' in data['categories'], 'QUAL-ERR not found in registry'
PYEOF
}

@test "category-registry: QUAL-COMPLEX subcategory exists" {
  python3 - "$REGISTRY" <<'PYEOF' || fail "QUAL-COMPLEX subcategory missing from category registry"
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
assert 'QUAL-COMPLEX' in data['categories'], 'QUAL-COMPLEX not found in registry'
PYEOF
}

@test "category-registry: COST-THROTTLE-IMPL declared" {
  run python3 - "$REGISTRY" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1]))
ids = list(r.get('categories') or {})
assert 'COST-THROTTLE-IMPL' in ids
print('ok')
PYEOF
  assert_success
}

@test "category-registry: EST-DRIFT severity restricted to WARNING" {
  run python3 - "$REGISTRY" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1]))
cats = r.get('categories') or {}
c = cats.get('EST-DRIFT')
assert c is not None, 'EST-DRIFT not found'
assert c.get('severity_allowed') == ['WARNING'], c
print('ok')
PYEOF
  assert_success
}

@test "category-registry: COST-DOWNGRADE / COST-ESCALATION-AUTO / COST-ESCALATION-TIMEOUT declared" {
  run python3 - "$REGISTRY" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1]))
ids = list(r.get('categories') or {})
for cat in ('COST-DOWNGRADE', 'COST-ESCALATION-AUTO', 'COST-ESCALATION-TIMEOUT'):
    assert cat in ids, f'{cat} missing'
print('ok')
PYEOF
  assert_success
}

@test "category-registry: COST-* wildcard prefix registered" {
  run python3 - "$REGISTRY" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1]))
cats = r.get('categories') or {}
cost = cats.get('COST')
assert cost is not None, 'COST wildcard not declared'
assert cost.get('wildcard') is True, cost
print('ok')
PYEOF
  assert_success
}
