#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/swiftlint.sh

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/swiftlint.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
SWIFTLINT_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/swiftlint-sample.json"

# ---------------------------------------------------------------------------
# Python parser extracted from swiftlint.sh
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
sl_map = full_map.get('swiftlint', {})

def lookup_severity(swift_sev, rule_id):
    return sl_map.get(swift_sev, 'INFO')

def map_category(rule_id):
    rule = rule_id.lower()
    if any(k in rule for k in ('force_cast', 'force_try', 'force_unwrap')):
        return 'SW-LINT-SAFETY'
    if any(k in rule for k in ('complexity', 'length', 'size')):
        return 'SW-LINT-COMPLEX'
    if any(k in rule for k in ('unused', 'redundant')):
        return 'SW-LINT-CLEAN'
    return 'SW-LINT-STYLE'

with open(raw_path) as f:
    try:
        findings = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)

if not isinstance(findings, list):
    sys.exit(0)

for item in findings:
    fp = item.get('file', '?')
    ln = item.get('line', 0)
    reason = item.get('reason', '')
    rule_id = item.get('rule_id', '')
    swift_sev = item.get('severity', 'warning').lower()

    reason = reason.replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
    severity = lookup_severity(swift_sev, rule_id)
    category = map_category(rule_id)
    print(f'{fp}:{ln} | {category} | {severity} | {reason} | swiftlint [{rule_id}]')
" "$sev_map" "$raw"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "swiftlint adapter: exits non-zero when swiftlint not available" {
  local save_path="$PATH"
  PATH="/usr/bin:/bin"
  run bash "$ADAPTER" "/tmp" "." "$SEV_MAP"
  PATH="$save_path"
  [[ $status -eq 1 ]]
}

@test "swiftlint adapter: parses 3 findings from fixture" {
  run run_parser "$SEV_MAP" "$SWIFTLINT_FIXTURE"
  assert_success
  local line_count
  line_count="$(echo "$output" | grep -c '|')"
  [[ "$line_count" -eq 3 ]]
}

@test "swiftlint adapter: force_cast maps to SW-LINT-SAFETY" {
  run run_parser "$SEV_MAP" "$SWIFTLINT_FIXTURE"
  assert_success
  echo "$output" | grep "force_cast" | grep -q "SW-LINT-SAFETY"
}

@test "swiftlint adapter: line_length maps to SW-LINT-COMPLEX" {
  run run_parser "$SEV_MAP" "$SWIFTLINT_FIXTURE"
  assert_success
  echo "$output" | grep "line_length" | grep -q "SW-LINT-COMPLEX"
}

@test "swiftlint adapter: unused_import maps to SW-LINT-CLEAN" {
  run run_parser "$SEV_MAP" "$SWIFTLINT_FIXTURE"
  assert_success
  echo "$output" | grep "unused_import" | grep -q "SW-LINT-CLEAN"
}

@test "swiftlint adapter: error severity maps to WARNING" {
  run run_parser "$SEV_MAP" "$SWIFTLINT_FIXTURE"
  assert_success
  # force_cast has severity=Error → error → WARNING
  echo "$output" | grep "force_cast" | grep -q "| WARNING |"
}

@test "swiftlint adapter: warning severity maps to INFO" {
  run run_parser "$SEV_MAP" "$SWIFTLINT_FIXTURE"
  assert_success
  # line_length has severity=Warning → warning → INFO
  echo "$output" | grep "line_length" | grep -q "| INFO |"
}

@test "swiftlint adapter: file:line format preserved" {
  run run_parser "$SEV_MAP" "$SWIFTLINT_FIXTURE"
  assert_success
  echo "$output" | grep -q "Sources/App/Models/User.swift:15"
  echo "$output" | grep -q "Sources/App/Controllers/AuthController.swift:42"
}

@test "swiftlint adapter: empty input produces no output" {
  local empty_file="${TEST_TEMP}/empty.json"
  : > "$empty_file"
  run run_parser "$SEV_MAP" "$empty_file"
  assert_success
  [[ -z "$output" ]]
}

@test "swiftlint adapter: non-array input handled gracefully" {
  local obj_file="${TEST_TEMP}/object.json"
  printf '{"not": "an array"}\n' > "$obj_file"
  run run_parser "$SEV_MAP" "$obj_file"
  assert_success
  [[ -z "$output" ]]
}
