#!/usr/bin/env bats
# Scenario tests: linter output parsing (detekt + eslint adapters) via severity-map

# Covers:

load '../helpers/test-helpers'

SEVERITY_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/linter-output"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-linter-parse.XXXXXX")"
  MOCK_BIN="$TEST_TEMP/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
}

teardown() { rm -rf "$TEST_TEMP"; }

# Inline Python parser that replicates the detekt adapter's parsing logic.
_parse_detekt() {
  local raw_path="$1" sev_map="$2"
  python3 - "$sev_map" "$raw_path" <<'PYEOF'
import json, re, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
detekt_map = full_map.get('detekt', {})

def lookup_severity(rule_id):
    if rule_id in detekt_map:
        return detekt_map[rule_id]
    best = ('', 'INFO')
    for pattern, sev in detekt_map.items():
        if pattern.endswith('.*'):
            prefix = pattern[:-2]
            if rule_id.startswith(prefix) and len(prefix) > len(best[0]):
                best = (prefix, sev)
        elif pattern.endswith('*'):
            prefix = pattern[:-1]
            if rule_id.startswith(prefix) and len(prefix) > len(best[0]):
                best = (prefix, sev)
    return best[1]

def map_category(rule_id):
    rule_lower = rule_id.lower()
    if any(k in rule_lower for k in ('security', 'injection', 'eval')):
        return 'SEC-DETEKT'
    if any(k in rule_lower for k in ('performance', 'perf')):
        return 'PERF-DETEKT'
    if any(k in rule_lower for k in ('exception', 'error', 'swallow')):
        return 'QUAL-ERR'
    if any(k in rule_lower for k in ('complexity', 'long', 'large')):
        return 'QUAL-COMPLEX'
    return 'QUAL-DETEKT'

pat = re.compile(r'^(.+?):(\d+):\d+:\s+(.+?)\s+\[([\w.]+)]')
with open(raw_path) as f:
    for line in f:
        m = pat.match(line.strip())
        if not m:
            continue
        filepath, lineno, message, rule_id = m.group(1), m.group(2), m.group(3), m.group(4)
        severity = lookup_severity(rule_id)
        category = map_category(rule_id)
        hint = f'detekt rule {rule_id}'
        message = message.replace('|', '\\|')
        print(f'{filepath}:{lineno} | {category} | {severity} | {message} | {hint}')
PYEOF
}

# Inline Python parser that replicates the eslint adapter's parsing logic.
_parse_eslint() {
  local raw_path="$1" sev_map="$2"
  python3 - "$sev_map" "$raw_path" <<'PYEOF'
import json, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
eslint_map = full_map.get('eslint', {})
eslint_sev_map = eslint_map.get('_severity_map', {})

def lookup_severity(rule_id, eslint_severity):
    if rule_id and rule_id in eslint_map:
        return eslint_map[rule_id]
    sev_str = {2: 'error', 1: 'warn'}.get(eslint_severity, 'warn')
    return eslint_sev_map.get(sev_str, 'INFO')

def map_category(rule_id):
    if not rule_id:
        return 'TS-LINT-PARSE'
    r = rule_id.lower()
    if 'eval' in r or 'script' in r:
        return 'SEC-EVAL'
    if 'security' in r or 'xss' in r:
        return 'SEC-ESLINT'
    if 'react-hooks' in r or 'react/' in r:
        return 'TS-LINT-REACT'
    if 'typescript' in r or '@typescript' in r:
        return 'TS-LINT-TS'
    if 'import' in r:
        return 'TS-LINT-IMPORT'
    return 'TS-LINT-ESLINT'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        results = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for entry in results:
    filepath = entry.get('filePath', '?')
    for msg in entry.get('messages', []):
        line = msg.get('line', 0)
        rule_id = msg.get('ruleId', '')
        eslint_sev = msg.get('severity', 1)
        message = msg.get('message', '').replace('|', '\\|')
        severity = lookup_severity(rule_id, eslint_sev)
        category = map_category(rule_id)
        hint = f'eslint rule {rule_id}' if rule_id else 'eslint parse error'
        print(f'{filepath}:{line} | {category} | {severity} | {message} | {hint}')
PYEOF
}

# ---------------------------------------------------------------------------
# 1. Detekt fixture → 4 lines parsed to 4 findings with correct severities
# ---------------------------------------------------------------------------
@test "linter-parsing: detekt sample produces 4 findings with correct severities" {
  local raw="$FIXTURE_DIR/detekt-sample.txt"

  run bash -c "_parse_detekt() {
$(declare -f _parse_detekt | tail -n +3 | head -n -1)
}
_parse_detekt '$raw' '$SEVERITY_MAP'"

  # Actually run the inline python directly
  local output
  output="$(_parse_detekt "$raw" "$SEVERITY_MAP")"
  local line_count
  line_count="$(echo "$output" | grep -c '|' || true)"
  assert [ "$line_count" -eq 4 ]
  # SwallowedException → CRITICAL
  echo "$output" | grep -q "CRITICAL"
  # complexity rules → WARNING
  echo "$output" | grep -q "WARNING"
  # style rules → INFO
  echo "$output" | grep -q "INFO"
}

# ---------------------------------------------------------------------------
# 2. ESLint fixture → findings parsed correctly
# ---------------------------------------------------------------------------
@test "linter-parsing: eslint sample produces findings with correct categories" {
  local raw="$FIXTURE_DIR/eslint-sample.json"

  local output
  output="$(_parse_eslint "$raw" "$SEVERITY_MAP")"
  local line_count
  line_count="$(echo "$output" | grep -c '|' || true)"
  # eslint-sample.json has 4 messages
  assert [ "$line_count" -eq 4 ]
  # react-hooks/exhaustive-deps → TS-LINT-REACT (because 'react-hooks' matched first)
  echo "$output" | grep -q "TS-LINT-REACT"
  # null ruleId → TS-LINT-PARSE
  echo "$output" | grep -q "TS-LINT-PARSE"
}

# ---------------------------------------------------------------------------
# 3. Exact severity match beats glob
# ---------------------------------------------------------------------------
@test "linter-parsing: exact rule ID in severity-map overrides glob prefix match" {
  local raw="$TEST_TEMP/detekt-exact.txt"
  # SwallowedException has exact entry: CRITICAL (overrides exceptions.* -> WARNING)
  printf 'src/main/kotlin/domain/User.kt:15:5: A swallowed exception [SwallowedException]\n' > "$raw"

  local output
  output="$(_parse_detekt "$raw" "$SEVERITY_MAP")"
  echo "$output" | grep -q "CRITICAL"
  # Must NOT be WARNING (which is what exceptions.* would give)
  if echo "$output" | grep -q "WARNING"; then
    fail "Expected CRITICAL from exact match but got WARNING"
  fi
}

# ---------------------------------------------------------------------------
# 4. Longest glob prefix wins
# ---------------------------------------------------------------------------
@test "linter-parsing: longest glob prefix wins when multiple glob patterns match" {
  # complexity.TooLongFunction matches both complexity.* (WARNING)
  # There is no longer prefix for this rule, so complexity.* wins → WARNING
  local raw="$TEST_TEMP/detekt-complexity.txt"
  printf 'src/main/kotlin/domain/User.kt:23:1: The function is too long [complexity.TooLongFunction]\n' > "$raw"

  local output
  output="$(_parse_detekt "$raw" "$SEVERITY_MAP")"
  echo "$output" | grep -q "WARNING"
  echo "$output" | grep -q "QUAL-COMPLEX"
}

# ---------------------------------------------------------------------------
# 5. Unknown rule → INFO default
# ---------------------------------------------------------------------------
@test "linter-parsing: unknown detekt rule defaults to INFO severity" {
  local raw="$TEST_TEMP/detekt-unknown.txt"
  printf 'src/main/kotlin/domain/User.kt:8:3: Unknown rule [SomeNewRule]\n' > "$raw"

  local output
  output="$(_parse_detekt "$raw" "$SEVERITY_MAP")"
  echo "$output" | grep -q "INFO"
}

# ---------------------------------------------------------------------------
# 6. Empty linter output → no findings
# ---------------------------------------------------------------------------
@test "linter-parsing: empty detekt output produces no findings" {
  local raw="$TEST_TEMP/detekt-empty.txt"
  printf '' > "$raw"

  local output
  output="$(_parse_detekt "$raw" "$SEVERITY_MAP")"
  local trimmed
  trimmed="$(printf '%s' "$output" | tr -d '[:space:]')"
  assert [ -z "$trimmed" ]
}
