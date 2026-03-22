#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/eslint.sh
# The Python parsing logic is extracted and called directly with fixture data,
# so tests run without eslint/npx being installed.

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/eslint.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
ESLINT_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/eslint-sample.json"

# ---------------------------------------------------------------------------
# Python snippet extracted from eslint.sh — used by parsing tests.
# Accepts: $1=sev_map_path  $2=raw_path
# ---------------------------------------------------------------------------
run_parser() {
  local sev_map="$1"
  local raw="$2"
  python3 -c "
import json, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
eslint_map = full_map.get('eslint', {})
eslint_sev_map = eslint_map.get('_severity_map', {})

def lookup_severity(rule_id, eslint_severity):
    # exact rule match first
    if rule_id and rule_id in eslint_map:
        return eslint_map[rule_id]
    # fall back to eslint severity number -> string -> mapped severity
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
        message = msg.get('message', '').replace('|', '-')
        severity = lookup_severity(rule_id, eslint_sev)
        category = map_category(rule_id)
        hint = f'eslint rule {rule_id}' if rule_id else 'eslint parse error'
        print(f'{filepath}:{line} | {category} | {severity} | {message} | {hint}')
" "$sev_map" "$raw"
}

# ---------------------------------------------------------------------------
# 1. Exits non-zero when eslint/npx not available
# ---------------------------------------------------------------------------
@test "eslint adapter: exits non-zero when npx not available" {
  local fake_project="${TEST_TEMP}/no-eslint-project"
  mkdir -p "$fake_project"

  # Create a mock npx that always fails its availability check
  mock_command "npx" 'exit 1'

  run bash "$ADAPTER" "$fake_project" "$fake_project" "$SEV_MAP"

  # Should fail with exit code 1 (not installed) or 127 (command not found)
  assert_failure
}

# ---------------------------------------------------------------------------
# 2. Parses eslint JSON output correctly — all 4 messages from fixture
# ---------------------------------------------------------------------------
@test "eslint parser: parses all 4 messages from fixture" {
  run run_parser "$SEV_MAP" "$ESLINT_FIXTURE"
  assert_success

  local line_count
  line_count=$(printf '%s\n' "$output" | grep -c '|' || true)
  assert_equal "$line_count" "4"
}

# ---------------------------------------------------------------------------
# 3. Exact rule match: react-hooks/exhaustive-deps → WARNING
# ---------------------------------------------------------------------------
@test "eslint parser: react-hooks/exhaustive-deps maps to WARNING (exact match)" {
  local raw="${TEST_TEMP}/react-hooks.json"
  printf '[{"filePath":"src/App.tsx","messages":[{"ruleId":"react-hooks/exhaustive-deps","severity":1,"message":"Missing dependency","line":25}]}]\n' \
    > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "WARNING"
}

# ---------------------------------------------------------------------------
# 4. Exact rule match: @typescript-eslint/no-explicit-any → WARNING
# ---------------------------------------------------------------------------
@test "eslint parser: @typescript-eslint/no-explicit-any maps to WARNING (exact match)" {
  local raw="${TEST_TEMP}/ts-any.json"
  printf '[{"filePath":"src/App.tsx","messages":[{"ruleId":"@typescript-eslint/no-explicit-any","severity":1,"message":"Unexpected any","line":30}]}]\n' \
    > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "WARNING"
}

# ---------------------------------------------------------------------------
# 5. Unknown rule falls back to eslint severity mapping: severity 1 (warn) → INFO
# ---------------------------------------------------------------------------
@test "eslint parser: unknown rule with severity 1 (warn) falls back to INFO" {
  local raw="${TEST_TEMP}/unknown-rule.json"
  printf '[{"filePath":"src/App.tsx","messages":[{"ruleId":"some-unknown-rule","severity":1,"message":"Unknown","line":40}]}]\n' \
    > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "INFO"
}

# ---------------------------------------------------------------------------
# 6. null ruleId with severity 2 (error) → WARNING via _severity_map
# ---------------------------------------------------------------------------
@test "eslint parser: null ruleId with severity 2 maps to WARNING via _severity_map" {
  local raw="${TEST_TEMP}/null-rule.json"
  printf '[{"filePath":"src/App.tsx","messages":[{"ruleId":null,"severity":2,"message":"Parsing error: unexpected token","line":1}]}]\n' \
    > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "WARNING"
}

# ---------------------------------------------------------------------------
# 7. Category mapping: react-hooks/* → TS-LINT-REACT
# ---------------------------------------------------------------------------
@test "eslint parser: react-hooks rule maps to category TS-LINT-REACT" {
  local raw="${TEST_TEMP}/react-cat.json"
  printf '[{"filePath":"src/App.tsx","messages":[{"ruleId":"react-hooks/exhaustive-deps","severity":1,"message":"Missing dependency","line":25}]}]\n' \
    > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "TS-LINT-REACT"
}

# ---------------------------------------------------------------------------
# 8. Empty JSON array → no findings
# ---------------------------------------------------------------------------
@test "eslint parser: empty JSON array produces no findings" {
  local raw="${TEST_TEMP}/empty.json"
  printf '[]\n' > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# 9. no-eval rule maps to CRITICAL severity and SEC-EVAL category
# ---------------------------------------------------------------------------
@test "eslint parser: no-eval rule maps to CRITICAL severity" {
  # Create fixture with no-eval finding
  local raw="$TEST_TEMP/no-eval.json"
  cat > "$raw" << 'EOF'
[{"filePath":"src/app.ts","messages":[{"ruleId":"no-eval","severity":2,"message":"eval can be harmful","line":5}]}]
EOF

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "CRITICAL"
  assert_output --partial "SEC-EVAL"
}
