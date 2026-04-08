#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/checkstyle.sh

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/checkstyle.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
CHECKSTYLE_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/checkstyle-sample.txt"

# ---------------------------------------------------------------------------
# Python parser extracted from checkstyle.sh
# ---------------------------------------------------------------------------
run_parser() {
  local sev_map="$1"
  local raw="$2"
  python3 -c "
import json, re, sys
with open(sys.argv[1]) as f: full_map = json.load(f)
cs_map = full_map.get('checkstyle', {})

def lookup_sev(cs_sev): return cs_map.get(cs_sev.upper(), 'INFO')

def map_cat(msg):
    m = msg.lower()
    if any(k in m for k in ('javadoc','comment')): return 'JV-LINT-DOC'
    if any(k in m for k in ('import','unused')): return 'JV-LINT-IMPORT'
    if any(k in m for k in ('whitespace','indent','spacing')): return 'JV-LINT-FORMAT'
    if any(k in m for k in ('naming','name','abbreviation')): return 'JV-LINT-NAMING'
    return 'JV-LINT-STYLE'

pat_plain = re.compile(r'^\[(ERROR|WARNING|INFO)]\s+(.+?):(\d+)(?::\d+)?:\s+(.+)$')
pat_alt = re.compile(r'^(.+?):(\d+)(?::\d+)?:\s+(.+)$')
with open(sys.argv[2]) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('Starting') or line.startswith('Audit done'): continue
        m = pat_plain.match(line)
        if m:
            cs_sev, fp, ln, msg = m.groups()
            msg = msg.replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
            print(f'{fp}:{ln} | {map_cat(msg)} | {lookup_sev(cs_sev)} | {msg} | checkstyle')
            continue
        m = pat_alt.match(line)
        if m:
            fp, ln, msg = m.groups()
            msg = msg.replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
            print(f'{fp}:{ln} | {map_cat(msg)} | INFO | {msg} | checkstyle')
" "$sev_map" "$raw"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "checkstyle adapter: exits non-zero when checkstyle not available" {
  local save_path="$PATH"
  PATH="/usr/bin:/bin"
  run bash "$ADAPTER" "/tmp" "." "$SEV_MAP"
  PATH="$save_path"
  [[ $status -eq 1 ]]
}

@test "checkstyle adapter: parses 4 findings from fixture" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  local line_count
  line_count="$(echo "$output" | grep -c '|')"
  [[ "$line_count" -eq 4 ]]
}

@test "checkstyle adapter: Javadoc message maps to JV-LINT-DOC" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  echo "$output" | grep "Javadoc" | grep -q "JV-LINT-DOC"
}

@test "checkstyle adapter: unused import maps to JV-LINT-IMPORT" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  echo "$output" | grep "Unused import" | grep -q "JV-LINT-IMPORT"
}

@test "checkstyle adapter: indent message maps to JV-LINT-FORMAT" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  echo "$output" | grep "indent" | grep -q "JV-LINT-FORMAT"
}

@test "checkstyle adapter: abbreviation message maps to JV-LINT-NAMING" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  echo "$output" | grep "Abbreviation" | grep -q "JV-LINT-NAMING"
}

@test "checkstyle adapter: ERROR severity maps to WARNING" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  echo "$output" | grep "Javadoc" | grep -q "| WARNING |"
}

@test "checkstyle adapter: WARNING severity maps to INFO" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  echo "$output" | grep "Unused import" | grep -q "| INFO |"
}

@test "checkstyle adapter: alt format (no severity prefix) maps to INFO" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  # The abbreviation line has no [ERROR]/[WARNING] prefix — alt pattern → INFO default
  echo "$output" | grep "Abbreviation" | grep -q "| INFO |"
}

@test "checkstyle adapter: file:line format preserved" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  echo "$output" | grep -q "src/main/java/com/example/App.java:15"
  echo "$output" | grep -q "src/main/java/com/example/service/UserService.java:8"
}

@test "checkstyle adapter: Starting/Audit lines skipped" {
  run run_parser "$SEV_MAP" "$CHECKSTYLE_FIXTURE"
  assert_success
  # Should NOT contain "Starting audit" or "Audit done" in output
  ! echo "$output" | grep -q "Starting"
  ! echo "$output" | grep -q "Audit done"
}

@test "checkstyle adapter: empty input produces no output" {
  local empty_file="${TEST_TEMP}/empty.txt"
  : > "$empty_file"
  run run_parser "$SEV_MAP" "$empty_file"
  assert_success
  [[ -z "$output" ]]
}
