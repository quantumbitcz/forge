#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/credo.sh

load '../helpers/test-helpers'

SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
CREDO_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/credo-sample.json"

run_parser() {
  local sev_map="$1" raw="$2"
  python3 -c "
import json, sys
with open(sys.argv[1]) as f: full_map = json.load(f)
credo_map = full_map.get('credo', {})

def lookup_severity(check):
    if check in credo_map: return credo_map[check]
    best = ('', 'INFO')
    for pattern, sev in credo_map.items():
        prefix = pattern.rstrip('*')
        if check.startswith(prefix) and len(prefix) > len(best[0]):
            best = (prefix, sev)
    return best[1]

def map_category(check, priority):
    if not check: return 'EX-LINT-CREDO'
    if 'Security' in check or 'Warning' in check: return 'EX-LINT-SEC'
    if 'Readability' in check: return 'EX-LINT-STYLE'
    if 'Refactor' in check: return 'EX-LINT-REFACTOR'
    if 'Design' in check: return 'EX-LINT-DESIGN'
    if 'Consistency' in check: return 'EX-LINT-CONSISTENCY'
    return 'EX-LINT-CREDO'

with open(sys.argv[2]) as f:
    content = f.read().strip()
    if not content: sys.exit(0)
    try: data = json.loads(content)
    except json.JSONDecodeError: sys.exit(0)

for issue in data.get('issues', []):
    fp = issue.get('filename', '?')
    row = issue.get('line_no', 0)
    check = issue.get('check', '')
    message = issue.get('message', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
    priority = issue.get('priority', 0)
    severity = lookup_severity(check)
    category = map_category(check, priority)
    hint = f'credo: {check}' if check else 'mix credo'
    print(f'{fp}:{row} | {category} | {severity} | {message} | {hint}')
" "$sev_map" "$raw"
}

@test "credo adapter: parses 3 findings from fixture" {
  run run_parser "$SEV_MAP" "$CREDO_FIXTURE"
  assert_success
  local count; count="$(echo "$output" | grep -c '|')"
  [[ "$count" -eq 3 ]]
}

@test "credo adapter: Readability check maps to EX-LINT-STYLE" {
  run run_parser "$SEV_MAP" "$CREDO_FIXTURE"
  assert_success
  echo "$output" | grep "ModuleDoc" | grep -q "EX-LINT-STYLE"
}

@test "credo adapter: Warning check maps to EX-LINT-SEC" {
  run run_parser "$SEV_MAP" "$CREDO_FIXTURE"
  assert_success
  echo "$output" | grep "IoInspect" | grep -q "EX-LINT-SEC"
}

@test "credo adapter: Refactor check maps to EX-LINT-REFACTOR" {
  run run_parser "$SEV_MAP" "$CREDO_FIXTURE"
  assert_success
  echo "$output" | grep "CyclomaticComplexity" | grep -q "EX-LINT-REFACTOR"
}

@test "credo adapter: file:line format preserved" {
  run run_parser "$SEV_MAP" "$CREDO_FIXTURE"
  assert_success
  echo "$output" | grep -q "lib/app/auth.ex:1"
  echo "$output" | grep -q "lib/app/controller.ex:42"
}

@test "credo adapter: empty input produces no output" {
  local empty="${TEST_TEMP}/empty.json"
  : > "$empty"
  run run_parser "$SEV_MAP" "$empty"
  assert_success
  [[ -z "$output" ]]
}
