#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/yamllint.sh
# The Python parsing logic is extracted and called directly with fixture data.

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/yamllint.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
YAMLLINT_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/yamllint-sample.txt"

# ---------------------------------------------------------------------------
# Parser extracted from yamllint.sh — accepts: $1=sev_map  $2=raw
# ---------------------------------------------------------------------------
run_parser() {
  local sev_map="$1" raw="$2"
  python3 -c "
import json, sys, re

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
yamllint_map = full_map.get('yamllint', {})

def lookup_severity(level):
    sev_map = yamllint_map.get('_severity_map', {})
    if level in sev_map:
        return sev_map[level]
    if level == 'error':
        return 'WARNING'
    return 'INFO'

pattern = re.compile(r'^(.+?):(\d+):\d+: \[(\w+)\] (.+?)(?:\s+\((\S+)\))?\$')

with open(raw_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        m = pattern.match(line)
        if not m:
            continue
        filepath, lineno, level, message, rule = m.groups()
        rule = rule or 'general'
        severity = lookup_severity(level)
        safe_msg = message.replace('|', '\\\\|')
        hint = f'yamllint rule: {rule}'
        print(f'{filepath}:{lineno} | YML-LINT | {severity} | {safe_msg} | {hint}')
" "$sev_map" "$raw"
}

# ---------------------------------------------------------------------------
# 1. Adapter script exists and is executable
# ---------------------------------------------------------------------------
@test "yamllint-adapter: script exists and is executable" {
  [[ -x "$ADAPTER" ]]
}

# ---------------------------------------------------------------------------
# 2. Parser produces correct number of findings from fixture
# ---------------------------------------------------------------------------
@test "yamllint-adapter: parses 3 findings from fixture" {
  run run_parser "$SEV_MAP" "$YAMLLINT_FIXTURE"
  assert_success
  local count
  count="$(printf '%s' "$output" | grep -c '|' || true)"
  assert [ "$count" -eq 3 ]
}

# ---------------------------------------------------------------------------
# 3. Error level maps to WARNING severity
# ---------------------------------------------------------------------------
@test "yamllint-adapter: error level maps to WARNING" {
  run run_parser "$SEV_MAP" "$YAMLLINT_FIXTURE"
  assert_success
  assert_output --partial "WARNING"
}

# ---------------------------------------------------------------------------
# 4. Warning level maps to INFO severity
# ---------------------------------------------------------------------------
@test "yamllint-adapter: warning level maps to INFO" {
  run run_parser "$SEV_MAP" "$YAMLLINT_FIXTURE"
  assert_success
  assert_output --partial "INFO"
}

# ---------------------------------------------------------------------------
# 5. All findings use YML-LINT category
# ---------------------------------------------------------------------------
@test "yamllint-adapter: all findings use YML-LINT category" {
  run run_parser "$SEV_MAP" "$YAMLLINT_FIXTURE"
  assert_success
  local non_yml_count
  non_yml_count="$(printf '%s' "$output" | grep -v 'YML-LINT' | grep -c '|' || true)"
  assert [ "$non_yml_count" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 6. Output format matches standard finding format
# ---------------------------------------------------------------------------
@test "yamllint-adapter: output matches standard format" {
  run run_parser "$SEV_MAP" "$YAMLLINT_FIXTURE"
  assert_success
  assert_finding_format "$output"
}
