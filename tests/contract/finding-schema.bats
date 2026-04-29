#!/usr/bin/env bats
# Contract tests: agent output JSON schemas
# Validates finding-schema.json and dispatch-response-schema.json
# match the contracts defined in output-format.md and scoring.md.

load '../helpers/test-helpers'

FINDING_SCHEMA="$PLUGIN_ROOT/shared/checks/finding-schema.json"
DISPATCH_SCHEMA="$PLUGIN_ROOT/shared/checks/dispatch-response-schema.json"
OUTPUT_FORMAT="$PLUGIN_ROOT/shared/checks/output-format.md"
SCORING="$PLUGIN_ROOT/shared/scoring.md"

# ---------------------------------------------------------------------------
# 1. finding-schema.json is valid JSON
# ---------------------------------------------------------------------------
@test "finding-schema: schema is valid JSON" {
  [[ -f "$FINDING_SCHEMA" ]] || fail "finding-schema.json does not exist"
  python3 - "$FINDING_SCHEMA" <<'PYEOF' || fail "finding-schema.json is not valid JSON"
import json, sys
json.load(open(sys.argv[1]))
PYEOF
}

# ---------------------------------------------------------------------------
# 2. Required fields match output-format.md
# ---------------------------------------------------------------------------
@test "finding-schema: required fields match output-format.md" {
  # output-format.md defines 5+1 fields: file, line, CATEGORY-CODE, SEVERITY, message, fix_hint.
  # confidence (6th) is optional.
  # category, severity, description, fix_hint are top-level required.
  # file + line are conditionally required for non-INTENT findings via the allOf branch
  # (INTENT-* findings are AC-scoped and may have file/line null — see Phase 7 fg-540).
  local required
  required=$(python3 - "$FINDING_SCHEMA" <<'PYEOF'
import json, sys
schema = json.load(open(sys.argv[1]))
print(' '.join(sorted(schema['required'])))
PYEOF
)
  for field in "category" "severity" "description" "fix_hint"; do
    echo "$required" | grep -q "$field" \
      || fail "Required field '$field' missing from finding-schema.json top-level required"
  done

  # file + line: required via allOf (non-INTENT branch) — assert the conditional shape exists.
  python3 - "$FINDING_SCHEMA" <<'PYEOF' || fail "file/line must be conditionally required via allOf for non-INTENT findings"
import json, sys
schema = json.load(open(sys.argv[1]))
all_of = schema.get('allOf', [])
non_intent_required = []
for branch in all_of:
    then_block = branch.get('then', {})
    non_intent_required.extend(then_block.get('required', []))
assert 'file' in non_intent_required, 'file must be conditionally required for non-INTENT findings'
assert 'line' in non_intent_required, 'line must be conditionally required for non-INTENT findings'
PYEOF

  # Confidence should NOT be in required.
  echo "$required" | grep -qv "confidence" \
    || fail "confidence should not be required (it's optional per output-format.md)"
}

# ---------------------------------------------------------------------------
# 3. Severity enum matches scoring.md
# ---------------------------------------------------------------------------
@test "finding-schema: severity enum matches scoring.md" {
  local severities
  severities=$(python3 - "$FINDING_SCHEMA" <<'PYEOF'
import json, sys
schema = json.load(open(sys.argv[1]))
print(' '.join(schema['properties']['severity']['enum']))
PYEOF
)
  for sev in "CRITICAL" "WARNING" "INFO"; do
    echo "$severities" | grep -q "$sev" \
      || fail "Severity '$sev' missing from finding-schema.json enum"
  done
}

# ---------------------------------------------------------------------------
# 4. Category pattern matches output-format.md
# ---------------------------------------------------------------------------
@test "finding-schema: category pattern matches output-format.md" {
  local pattern
  pattern=$(python3 - "$FINDING_SCHEMA" <<'PYEOF'
import json, sys
schema = json.load(open(sys.argv[1]))
print(schema['properties']['category']['pattern'])
PYEOF
)
  # Pattern should match uppercase with hyphens: ^[A-Z][A-Z0-9-]+$
  [[ "$pattern" == '^[A-Z][A-Z0-9-]+$' ]] \
    || fail "Category pattern should be '^[A-Z][A-Z0-9-]+\$', got '$pattern'"
}

# ---------------------------------------------------------------------------
# 5. dispatch-response-schema.json is valid JSON
# ---------------------------------------------------------------------------
@test "dispatch-response-schema: schema is valid JSON" {
  [[ -f "$DISPATCH_SCHEMA" ]] || fail "dispatch-response-schema.json does not exist"
  python3 - "$DISPATCH_SCHEMA" <<'PYEOF' || fail "dispatch-response-schema.json is not valid JSON"
import json, sys
json.load(open(sys.argv[1]))
PYEOF
}

# ---------------------------------------------------------------------------
# 6. maxItems = 100 (matches scoring.md findings cap)
# ---------------------------------------------------------------------------
@test "dispatch-response-schema: maxItems = 100" {
  local max_items
  max_items=$(python3 - "$DISPATCH_SCHEMA" <<'PYEOF'
import json, sys
schema = json.load(open(sys.argv[1]))
print(schema['properties']['findings']['maxItems'])
PYEOF
)
  [[ "$max_items" == "100" ]] \
    || fail "maxItems should be 100 (per scoring.md findings cap), got $max_items"
}
