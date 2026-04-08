#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/rubocop.sh

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/rubocop.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
RUBOCOP_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/rubocop-sample.json"

# ---------------------------------------------------------------------------
# Python parser extracted from rubocop.sh
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
rubocop_map = full_map.get('rubocop', {})

def lookup_severity(rb_severity, cop_name):
    if cop_name in rubocop_map:
        return rubocop_map[cop_name]
    best_cop = ('', '')
    for pattern, sev in rubocop_map.items():
        prefix = pattern.rstrip('*')
        if cop_name.startswith(prefix) and len(prefix) > len(best_cop[0]):
            best_cop = (prefix, sev)
    if best_cop[1]:
        return best_cop[1]
    cap = rb_severity.capitalize() if rb_severity else ''
    return rubocop_map.get(cap, 'INFO')

def map_category(cop_name):
    if not cop_name:
        return 'RB-LINT-RUBOCOP'
    parts = cop_name.split('/')
    dept = parts[0] if parts else ''
    if dept == 'Security':
        return 'RB-LINT-SEC'
    if dept == 'Performance':
        return 'RB-LINT-PERF'
    if dept in ('Layout', 'Style'):
        return 'RB-LINT-STYLE'
    if dept == 'Lint':
        return 'RB-LINT-BUG'
    if dept == 'Metrics':
        return 'RB-LINT-METRICS'
    return 'RB-LINT-RUBOCOP'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for file_entry in data.get('files', []):
    path = file_entry.get('path', '?')
    for offense in file_entry.get('offenses', []):
        loc = offense.get('location', {})
        row = loc.get('start_line', 0)
        cop = offense.get('cop_name', '')
        rb_severity = offense.get('severity', '')
        message = offense.get('message', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
        severity = lookup_severity(rb_severity, cop)
        category = map_category(cop)
        hint = f'rubocop cop {cop}' if cop else 'rubocop'
        print(f'{path}:{row} | {category} | {severity} | {message} | {hint}')
" "$sev_map" "$raw"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "rubocop adapter: exits non-zero when rubocop not available" {
  local save_path="$PATH"
  PATH="/usr/bin:/bin"
  run bash "$ADAPTER" "/tmp" "." "$SEV_MAP"
  PATH="$save_path"
  [[ $status -eq 1 ]]
}

@test "rubocop adapter: parses 4 findings from fixture" {
  run run_parser "$SEV_MAP" "$RUBOCOP_FIXTURE"
  assert_success
  local line_count
  line_count="$(echo "$output" | grep -c '|')"
  [[ "$line_count" -eq 4 ]]
}

@test "rubocop adapter: Layout cop maps to RB-LINT-STYLE" {
  run run_parser "$SEV_MAP" "$RUBOCOP_FIXTURE"
  assert_success
  echo "$output" | grep "Layout/IndentationWidth" | grep -q "RB-LINT-STYLE"
}

@test "rubocop adapter: Lint cop maps to RB-LINT-BUG" {
  run run_parser "$SEV_MAP" "$RUBOCOP_FIXTURE"
  assert_success
  echo "$output" | grep "Lint/UselessAssignment" | grep -q "RB-LINT-BUG"
}

@test "rubocop adapter: Security cop maps to RB-LINT-SEC" {
  run run_parser "$SEV_MAP" "$RUBOCOP_FIXTURE"
  assert_success
  echo "$output" | grep "Security/Eval" | grep -q "RB-LINT-SEC"
}

@test "rubocop adapter: Metrics cop maps to RB-LINT-METRICS" {
  run run_parser "$SEV_MAP" "$RUBOCOP_FIXTURE"
  assert_success
  echo "$output" | grep "Metrics/AbcSize" | grep -q "RB-LINT-METRICS"
}

@test "rubocop adapter: convention severity maps to INFO" {
  run run_parser "$SEV_MAP" "$RUBOCOP_FIXTURE"
  assert_success
  # Layout/IndentationWidth has severity=convention → Convention → INFO
  echo "$output" | grep "IndentationWidth" | grep -q "| INFO |"
}

@test "rubocop adapter: error severity maps to WARNING" {
  run run_parser "$SEV_MAP" "$RUBOCOP_FIXTURE"
  assert_success
  # Lint/UselessAssignment has severity=error → Error → WARNING
  echo "$output" | grep "UselessAssignment" | grep -q "| WARNING |"
}

@test "rubocop adapter: file:line format preserved" {
  run run_parser "$SEV_MAP" "$RUBOCOP_FIXTURE"
  assert_success
  echo "$output" | grep -q "app/models/user.rb:10"
  echo "$output" | grep -q "app/controllers/auth_controller.rb:42"
}

@test "rubocop adapter: empty input produces no output" {
  local empty_file="${TEST_TEMP}/empty.json"
  : > "$empty_file"
  run run_parser "$SEV_MAP" "$empty_file"
  assert_success
  [[ -z "$output" ]]
}
