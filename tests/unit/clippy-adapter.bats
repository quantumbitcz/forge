#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/clippy.sh
# Python parsing logic is extracted and called directly with fixture data,
# so tests run without cargo/clippy being installed.

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/clippy.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
CLIPPY_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/clippy-sample.json"

# ---------------------------------------------------------------------------
# Python parser extracted from clippy.sh — accepts: $1=sev_map  $2=raw_path
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
clippy_map = full_map.get('clippy', {})

def lookup_severity(level, lint_group):
    if lint_group in clippy_map:
        return clippy_map[lint_group]
    level_map = {'error': 'CRITICAL', 'warning': 'WARNING', 'note': 'INFO', 'help': 'INFO'}
    return level_map.get(level, 'INFO')

def extract_group_from_explanation(code_obj):
    if not code_obj or not isinstance(code_obj, dict):
        return ''
    explanation = code_obj.get('explanation') or ''
    for group in ('correctness', 'suspicious', 'perf', 'style', 'nursery', 'complexity', 'pedantic'):
        if group in explanation.lower():
            return group
    return ''

def map_category(level, lint_name):
    if 'unsafe' in lint_name or 'security' in lint_name:
        return 'RS-LINT-SEC'
    if 'perf' in lint_name:
        return 'RS-LINT-PERF'
    if level == 'error':
        return 'RS-LINT-ERR'
    return 'RS-LINT-CLIPPY'

with open(raw_path) as f:
    for raw_line in f:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            obj = json.loads(raw_line)
        except json.JSONDecodeError:
            continue

        if obj.get('reason') != 'compiler-message':
            continue

        msg = obj.get('message', {})
        if not msg:
            continue

        level = msg.get('level', 'warning')
        if level in ('note', 'help'):
            continue

        text = msg.get('message', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
        code_obj = msg.get('code')
        lint_name = ''
        if code_obj and isinstance(code_obj, dict):
            lint_name = code_obj.get('code', '')

        group = extract_group_from_explanation(code_obj)

        spans = msg.get('spans', [])
        if not spans:
            continue

        span = next((s for s in spans if s.get('is_primary')), spans[0])
        filepath = span.get('file_name', '?')
        line_start = span.get('line_start', 0)

        severity = lookup_severity(level, group)
        category = map_category(level, lint_name)
        hint = f'clippy lint {lint_name}' if lint_name else 'clippy warning'
        print(f'{filepath}:{line_start} | {category} | {severity} | {text} | {hint}')
" "$sev_map" "$raw"
}

# ---------------------------------------------------------------------------
# 1. Exits non-zero when cargo not available
# ---------------------------------------------------------------------------
@test "clippy adapter: exits non-zero when cargo not available" {
  # Hide cargo from PATH
  local save_path="$PATH"
  PATH="/usr/bin:/bin"
  run bash "$ADAPTER" "/tmp" "." "$SEV_MAP"
  PATH="$save_path"
  [[ $status -eq 1 ]]
}

# ---------------------------------------------------------------------------
# 2. Parses fixture data and produces expected number of findings
# ---------------------------------------------------------------------------
@test "clippy adapter: parses 3 findings from fixture (skips notes and non-compiler)" {
  run run_parser "$SEV_MAP" "$CLIPPY_FIXTURE"
  assert_success
  # 5 lines in fixture: 3 compiler-message with warning/error, 1 note (skipped), 1 build-script (skipped)
  local line_count
  line_count="$(echo "$output" | grep -c '|')"
  [[ "$line_count" -eq 3 ]]
}

# ---------------------------------------------------------------------------
# 3. Error-level finding maps to CRITICAL severity
# ---------------------------------------------------------------------------
@test "clippy adapter: error-level maps to CRITICAL and RS-LINT-ERR category" {
  run run_parser "$SEV_MAP" "$CLIPPY_FIXTURE"
  assert_success
  # The "too_many_arguments" finding is level=error
  echo "$output" | grep -q "RS-LINT-ERR | CRITICAL"
}

# ---------------------------------------------------------------------------
# 4. Warning-level finding maps to WARNING severity
# ---------------------------------------------------------------------------
@test "clippy adapter: warning-level maps to WARNING" {
  run run_parser "$SEV_MAP" "$CLIPPY_FIXTURE"
  assert_success
  echo "$output" | grep -q "| WARNING |"
}

# ---------------------------------------------------------------------------
# 5. Unsafe-related lint maps to RS-LINT-SEC category
# ---------------------------------------------------------------------------
@test "clippy adapter: unsafe lint maps to RS-LINT-SEC" {
  run run_parser "$SEV_MAP" "$CLIPPY_FIXTURE"
  assert_success
  echo "$output" | grep -q "RS-LINT-SEC"
}

# ---------------------------------------------------------------------------
# 6. File paths and line numbers are preserved
# ---------------------------------------------------------------------------
@test "clippy adapter: preserves file:line format" {
  run run_parser "$SEV_MAP" "$CLIPPY_FIXTURE"
  assert_success
  echo "$output" | grep -q "src/main.rs:5"
  echo "$output" | grep -q "src/lib.rs:12"
  echo "$output" | grep -q "src/ffi.rs:8"
}

# ---------------------------------------------------------------------------
# 7. Hint includes lint name
# ---------------------------------------------------------------------------
@test "clippy adapter: hint includes clippy lint name" {
  run run_parser "$SEV_MAP" "$CLIPPY_FIXTURE"
  assert_success
  echo "$output" | grep -q "clippy lint clippy::needless_pass_by_value"
  echo "$output" | grep -q "clippy lint clippy::too_many_arguments"
}

# ---------------------------------------------------------------------------
# 8. Empty input produces no output
# ---------------------------------------------------------------------------
@test "clippy adapter: empty input produces no output" {
  local empty_file="${TEST_TEMP}/empty.json"
  : > "$empty_file"
  run run_parser "$SEV_MAP" "$empty_file"
  assert_success
  [[ -z "$output" ]]
}
