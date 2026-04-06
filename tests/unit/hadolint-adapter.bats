#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/hadolint.sh
# The Python parsing logic is extracted and called directly with fixture data.

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/hadolint.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
HADOLINT_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/hadolint-sample.json"

# ---------------------------------------------------------------------------
# Parser extracted from hadolint.sh — accepts: $1=sev_map  $2=raw  $3=target
# ---------------------------------------------------------------------------
run_parser() {
  local sev_map="$1" raw="$2" target="$3"
  python3 -c "
import json, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]
target = sys.argv[3]

with open(sev_map_path) as f:
    full_map = json.load(f)
hadolint_map = full_map.get('hadolint', {})

def lookup_severity(level, code):
    if code in hadolint_map:
        return hadolint_map[code]
    sev_map = hadolint_map.get('_severity_map', {})
    if level in sev_map:
        return sev_map[level]
    level_lower = level.lower() if level else ''
    if level_lower == 'error':
        return 'WARNING'
    if level_lower == 'warning':
        return 'INFO'
    return 'INFO'

def map_category(code):
    if not code:
        return 'DF-LINT'
    c = code.upper()
    if c.startswith('DL'):
        num = int(c[2:]) if c[2:].isdigit() else 0
        if c == 'DL3002':
            return 'DF-LINT-SEC'
        if 3000 <= num < 5000:
            return 'DF-LINT-BEST'
    if c.startswith('SC'):
        return 'DF-LINT-SHELL'
    return 'DF-LINT'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    findings = json.loads(content)

for item in findings:
    line = item.get('line', 0)
    code = item.get('code', '')
    message = item.get('message', '').replace('|', '\\\\|')
    level = item.get('level', 'warning')
    severity = lookup_severity(level, code)
    category = map_category(code)
    hint = f'hadolint rule {code}' if code else 'hadolint check'
    print(f'{target}:{line} | {category} | {severity} | {message} | {hint}')
" "$sev_map" "$raw" "$target"
}

# ---------------------------------------------------------------------------
# 1. Adapter script exists and is executable
# ---------------------------------------------------------------------------
@test "hadolint-adapter: script exists and is executable" {
  [[ -x "$ADAPTER" ]]
}

# ---------------------------------------------------------------------------
# 2. Parser produces correct number of findings from fixture
# ---------------------------------------------------------------------------
@test "hadolint-adapter: parses 3 findings from fixture" {
  run run_parser "$SEV_MAP" "$HADOLINT_FIXTURE" "Dockerfile"
  assert_success
  local count
  count="$(printf '%s' "$output" | grep -c '|' || true)"
  assert [ "$count" -eq 3 ]
}

# ---------------------------------------------------------------------------
# 3. DL3002 maps to DF-LINT-SEC category
# ---------------------------------------------------------------------------
@test "hadolint-adapter: DL3002 maps to DF-LINT-SEC" {
  run run_parser "$SEV_MAP" "$HADOLINT_FIXTURE" "Dockerfile"
  assert_success
  assert_output --partial "DF-LINT-SEC"
}

# ---------------------------------------------------------------------------
# 4. DL3007 maps to DF-LINT-BEST category
# ---------------------------------------------------------------------------
@test "hadolint-adapter: DL3007 maps to DF-LINT-BEST" {
  run run_parser "$SEV_MAP" "$HADOLINT_FIXTURE" "Dockerfile"
  assert_success
  assert_output --partial "DF-LINT-BEST"
}

# ---------------------------------------------------------------------------
# 5. Output format matches standard finding format
# ---------------------------------------------------------------------------
@test "hadolint-adapter: output matches standard format" {
  run run_parser "$SEV_MAP" "$HADOLINT_FIXTURE" "Dockerfile"
  assert_success
  assert_finding_format "$output"
}
