#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/dart-analyzer.sh

load '../helpers/test-helpers'

SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
DART_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/dart-analyzer-sample.json"

run_parser() {
  local sev_map="$1" raw="$2"
  python3 -c "
import json, sys
with open(sys.argv[1]) as f: full_map = json.load(f)
dart_map = full_map.get('dart', {})

def lookup_severity(code, dart_severity):
    if code in dart_map: return dart_map[code]
    best = ('', None)
    for pattern, sev in dart_map.items():
        prefix = pattern.rstrip('*')
        if code.startswith(prefix) and len(prefix) > len(best[0]):
            best = (prefix, sev)
    if best[1]: return best[1]
    mapping = {'ERROR': 'CRITICAL', 'WARNING': 'WARNING', 'INFO': 'INFO'}
    return mapping.get(dart_severity, 'INFO')

def map_category(code):
    if not code: return 'DART-LINT'
    if 'deprecated' in code.lower(): return 'DART-LINT-DEPRECATION'
    if 'unused' in code.lower(): return 'DART-LINT-UNUSED'
    return 'DART-LINT'

with open(sys.argv[2]) as f:
    content = f.read().strip()
    if not content: sys.exit(0)
    try: data = json.loads(content)
    except json.JSONDecodeError: sys.exit(0)

for diag in data.get('diagnostics', []):
    fp = diag.get('location', {}).get('file', '?')
    row = diag.get('location', {}).get('range', {}).get('start', {}).get('line', 0)
    code = diag.get('code', '')
    message = diag.get('problemMessage', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
    dart_sev = diag.get('severity', 'INFO')
    severity = lookup_severity(code, dart_sev)
    category = map_category(code)
    hint = f'dart analyze: {code}' if code else 'dart analyze'
    print(f'{fp}:{row} | {category} | {severity} | {message} | {hint}')
" "$sev_map" "$raw"
}

@test "dart-analyzer adapter: parses 3 diagnostics from fixture" {
  run run_parser "$SEV_MAP" "$DART_FIXTURE"
  assert_success
  local count; count="$(echo "$output" | grep -c '|')"
  [[ "$count" -eq 3 ]]
}

@test "dart-analyzer adapter: unused code maps to DART-LINT-UNUSED" {
  run run_parser "$SEV_MAP" "$DART_FIXTURE"
  assert_success
  echo "$output" | grep "unused_import" | grep -q "DART-LINT-UNUSED"
}

@test "dart-analyzer adapter: deprecated code maps to DART-LINT-DEPRECATION" {
  run run_parser "$SEV_MAP" "$DART_FIXTURE"
  assert_success
  echo "$output" | grep "deprecated" | grep -q "DART-LINT-DEPRECATION"
}

@test "dart-analyzer adapter: ERROR severity maps to CRITICAL" {
  run run_parser "$SEV_MAP" "$DART_FIXTURE"
  assert_success
  echo "$output" | grep "invalid_assignment" | grep -q "| CRITICAL |"
}

@test "dart-analyzer adapter: file:line format preserved" {
  run run_parser "$SEV_MAP" "$DART_FIXTURE"
  assert_success
  echo "$output" | grep -q "lib/src/auth.dart:3"
  echo "$output" | grep -q "lib/src/model.dart:28"
}

@test "dart-analyzer adapter: empty input produces no output" {
  local empty="${TEST_TEMP}/empty.json"
  : > "$empty"
  run run_parser "$SEV_MAP" "$empty"
  assert_success
  [[ -z "$output" ]]
}
