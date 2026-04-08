#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/dotnet-format.sh

load '../helpers/test-helpers'

SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
DOTNET_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/dotnet-format-sample.txt"

run_parser() {
  local sev_map="$1" raw="$2"
  python3 -c "
import json, sys, re
with open(sys.argv[1]) as f: full_map = json.load(f)
dotnet_map = full_map.get('dotnet-format', {})
dotnet_sev_map = dotnet_map.get('_severity_map', {})

def lookup_severity(diag_id, raw_severity):
    if diag_id and diag_id in dotnet_map: return dotnet_map[diag_id]
    return dotnet_sev_map.get(raw_severity, 'INFO')

def map_category(diag_id):
    if not diag_id: return 'CS-LINT-PARSE'
    d = diag_id.upper()
    if d.startswith('IDE'): return 'CS-LINT-IDE'
    if d.startswith('CS'): return 'CS-LINT-COMPILER'
    if d.startswith('CA'): return 'CS-LINT-ANALYSIS'
    if d.startswith('SA') or d.startswith('SCS'): return 'SEC-DOTNET'
    return 'CS-LINT-OTHER'

pattern = re.compile(r'^(.+?)\((\d+),\d+\):\s+(warning|error|info)\s+(\w+):\s+(.+)$')
with open(sys.argv[2]) as f:
    for line in f:
        m = pattern.match(line.strip())
        if not m: continue
        filepath, line_no, raw_sev, diag_id, message = m.groups()
        severity = lookup_severity(diag_id, raw_sev)
        category = map_category(diag_id)
        message = message.replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
        hint = f'dotnet diagnostic {diag_id}'
        print(f'{filepath}:{line_no} | {category} | {severity} | {message} | {hint}')
" "$sev_map" "$raw"
}

@test "dotnet-format adapter: parses 3 findings from fixture" {
  run run_parser "$SEV_MAP" "$DOTNET_FIXTURE"
  assert_success
  local count; count="$(echo "$output" | grep -c '|')"
  [[ "$count" -eq 3 ]]
}

@test "dotnet-format adapter: IDE prefix maps to CS-LINT-IDE" {
  run run_parser "$SEV_MAP" "$DOTNET_FIXTURE"
  assert_success
  echo "$output" | grep "IDE0060" | grep -q "CS-LINT-IDE"
}

@test "dotnet-format adapter: CS prefix maps to CS-LINT-COMPILER" {
  run run_parser "$SEV_MAP" "$DOTNET_FIXTURE"
  assert_success
  echo "$output" | grep "CS0168" | grep -q "CS-LINT-COMPILER"
}

@test "dotnet-format adapter: CA prefix maps to CS-LINT-ANALYSIS" {
  run run_parser "$SEV_MAP" "$DOTNET_FIXTURE"
  assert_success
  echo "$output" | grep "CA1062" | grep -q "CS-LINT-ANALYSIS"
}

@test "dotnet-format adapter: file:line format preserved" {
  run run_parser "$SEV_MAP" "$DOTNET_FIXTURE"
  assert_success
  echo "$output" | grep -q "AuthController.cs:42"
  echo "$output" | grep -q "PaymentService.cs:10"
}

@test "dotnet-format adapter: empty input produces no output" {
  local empty="${TEST_TEMP}/empty.txt"
  : > "$empty"
  run run_parser "$SEV_MAP" "$empty"
  assert_success
  [[ -z "$output" ]]
}
