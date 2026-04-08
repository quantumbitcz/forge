#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/android-lint.sh
# Tests both Android Lint XML parsing and detekt text parsing.

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/android-lint.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
LINT_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/android-lint-sample.xml"
DETEKT_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/android-detekt-sample.txt"

# ---------------------------------------------------------------------------
# Python parser extracted from android-lint.sh (dual XML + text parser)
# ---------------------------------------------------------------------------
run_parser() {
  local sev_map="$1"
  local lint_report="$2"
  local detekt_raw="$3"
  python3 -c "
import json, re, sys, os
from xml.etree import ElementTree as ET

sev_map_path = sys.argv[1]
lint_report  = sys.argv[2]
detekt_raw   = sys.argv[3]

with open(sev_map_path) as f:
    full_map = json.load(f)
android_map = full_map.get('android_lint', {})
detekt_map  = full_map.get('detekt', {})

def map_lint_severity(lint_sev, issue_id):
    if issue_id in android_map:
        return android_map[issue_id]
    return {'Fatal': 'CRITICAL', 'Error': 'WARNING', 'Warning': 'WARNING', 'Information': 'INFO'}.get(lint_sev, 'INFO')

def map_lint_category(category):
    cat = category.lower()
    if 'security' in cat:  return 'SEC-LINT'
    if 'performance' in cat: return 'PERF-LINT'
    if 'accessibility' in cat: return 'A11Y-LINT'
    if 'correctness' in cat: return 'QUAL-LINT'
    if 'usability' in cat: return 'QUAL-LINT'
    return 'ANDROID-LINT'

def map_detekt_severity(rule_id):
    if rule_id in detekt_map:
        return detekt_map[rule_id]
    rule_lower = rule_id.lower()
    if any(k in rule_lower for k in ('security', 'injection')):   return 'WARNING'
    if any(k in rule_lower for k in ('complexity', 'long')):      return 'INFO'
    return 'INFO'

if lint_report and os.path.isfile(lint_report):
    try:
        tree = ET.parse(lint_report)
        root = tree.getroot()
        for issue in root.findall('.//issue'):
            issue_id  = issue.get('id', 'unknown')
            lint_sev  = issue.get('severity', 'Warning')
            summary   = issue.get('summary', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
            category  = issue.get('category', 'Correctness')
            for loc in issue.findall('location'):
                filepath = loc.get('file', '?')
                line     = loc.get('line', '0')
                severity = map_lint_severity(lint_sev, issue_id)
                cat      = map_lint_category(category)
                hint     = f'android lint [{issue_id}]'
                print(f'{filepath}:{line} | {cat} | {severity} | {summary} | {hint}')
    except ET.ParseError:
        pass

pat = re.compile(r'^(.+?):(\d+):\d+:\s+(.+?)\s+\[([\w.]+)]')
with open(detekt_raw) as f:
    for line in f:
        m = pat.match(line.strip())
        if not m:
            continue
        filepath, lineno, message, rule_id = m.group(1), m.group(2), m.group(3), m.group(4)
        message  = message.replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
        severity = map_detekt_severity(rule_id)
        hint     = f'detekt rule {rule_id}'
        print(f'{filepath}:{lineno} | QUAL-DETEKT | {severity} | {message} | {hint}')
" "$sev_map" "$lint_report" "$detekt_raw"
}

# ---------------------------------------------------------------------------
# Android Lint XML parsing tests
# ---------------------------------------------------------------------------

@test "android-lint adapter: exits non-zero when gradlew not found" {
  run bash "$ADAPTER" "/tmp/nonexistent" "." "$SEV_MAP"
  [[ $status -eq 1 ]]
}

@test "android-lint adapter: parses 3 findings from XML fixture" {
  local empty_detekt="${TEST_TEMP}/empty-detekt.txt"
  : > "$empty_detekt"
  run run_parser "$SEV_MAP" "$LINT_FIXTURE" "$empty_detekt"
  assert_success
  local line_count
  line_count="$(echo "$output" | grep -c '|')"
  [[ "$line_count" -eq 3 ]]
}

@test "android-lint adapter: Security category maps to SEC-LINT" {
  local empty_detekt="${TEST_TEMP}/empty-detekt.txt"
  : > "$empty_detekt"
  run run_parser "$SEV_MAP" "$LINT_FIXTURE" "$empty_detekt"
  assert_success
  echo "$output" | grep "MissingPermission" | grep -q "SEC-LINT"
}

@test "android-lint adapter: Performance category maps to PERF-LINT" {
  local empty_detekt="${TEST_TEMP}/empty-detekt.txt"
  : > "$empty_detekt"
  run run_parser "$SEV_MAP" "$LINT_FIXTURE" "$empty_detekt"
  assert_success
  echo "$output" | grep "ObsoleteSdkInt" | grep -q "PERF-LINT"
}

@test "android-lint adapter: Error severity maps to WARNING" {
  local empty_detekt="${TEST_TEMP}/empty-detekt.txt"
  : > "$empty_detekt"
  run run_parser "$SEV_MAP" "$LINT_FIXTURE" "$empty_detekt"
  assert_success
  echo "$output" | grep "MissingPermission" | grep -q "| WARNING |"
}

@test "android-lint adapter: file:line format preserved from XML" {
  local empty_detekt="${TEST_TEMP}/empty-detekt.txt"
  : > "$empty_detekt"
  run run_parser "$SEV_MAP" "$LINT_FIXTURE" "$empty_detekt"
  assert_success
  echo "$output" | grep -q "activity_main.xml:12"
  echo "$output" | grep -q "ApiClient.kt:25"
}

# ---------------------------------------------------------------------------
# Detekt text parsing tests
# ---------------------------------------------------------------------------

@test "android-lint adapter: parses 2 detekt findings from text fixture" {
  run run_parser "$SEV_MAP" "/dev/null" "$DETEKT_FIXTURE"
  assert_success
  local line_count
  line_count="$(echo "$output" | grep -c '|')"
  [[ "$line_count" -eq 2 ]]
}

@test "android-lint adapter: detekt findings use QUAL-DETEKT category" {
  run run_parser "$SEV_MAP" "/dev/null" "$DETEKT_FIXTURE"
  assert_success
  echo "$output" | grep "LongMethod" | grep -q "QUAL-DETEKT"
}

@test "android-lint adapter: LongMethod maps to INFO via text heuristic" {
  run run_parser "$SEV_MAP" "/dev/null" "$DETEKT_FIXTURE"
  assert_success
  # 'long' in rule_id → INFO
  echo "$output" | grep "LongMethod" | grep -q "| INFO |"
}

# ---------------------------------------------------------------------------
# Combined output tests
# ---------------------------------------------------------------------------

@test "android-lint adapter: combined XML + detekt produces 5 findings" {
  run run_parser "$SEV_MAP" "$LINT_FIXTURE" "$DETEKT_FIXTURE"
  assert_success
  local line_count
  line_count="$(echo "$output" | grep -c '|')"
  [[ "$line_count" -eq 5 ]]
}

@test "android-lint adapter: empty inputs produce no output" {
  local empty_xml="${TEST_TEMP}/empty.xml"
  local empty_txt="${TEST_TEMP}/empty.txt"
  : > "$empty_xml"
  : > "$empty_txt"
  run run_parser "$SEV_MAP" "$empty_xml" "$empty_txt"
  assert_success
  [[ -z "$output" ]]
}
