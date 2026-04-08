#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/ruff.sh
# Python parsing logic is extracted and called directly with fixture data,
# so tests run without ruff being installed.

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/ruff.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
RUFF_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/ruff-sample.json"

# ---------------------------------------------------------------------------
# Python parser extracted from ruff.sh — accepts: $1=sev_map  $2=raw_path
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
ruff_map = full_map.get('ruff', {})

def lookup_severity(code):
    if code in ruff_map:
        return ruff_map[code]
    best = ('', 'INFO')
    for pattern, sev in ruff_map.items():
        prefix = pattern.rstrip('*')
        if code.startswith(prefix) and len(prefix) > len(best[0]):
            best = (prefix, sev)
    return best[1]

def map_category(code):
    if not code:
        return 'PY-LINT-RUFF'
    c = code.upper()
    if c.startswith('S'):
        return 'PY-LINT-SEC'
    if c.startswith('ASYNC'):
        return 'PY-LINT-ASYNC'
    if c.startswith('F'):
        return 'PY-LINT-PYFLAKES'
    if c.startswith('E') or c.startswith('W'):
        return 'PY-LINT-STYLE'
    if c.startswith('UP'):
        return 'PY-LINT-UPGRADE'
    if c.startswith('B'):
        return 'PY-LINT-BUGBEAR'
    return 'PY-LINT-RUFF'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        findings = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for item in findings:
    filename = item.get('filename', '?')
    loc = item.get('location', {})
    row = loc.get('row', 0)
    code = item.get('code', '')
    message = item.get('message', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
    severity = lookup_severity(code)
    category = map_category(code)
    hint = f'ruff rule {code}' if code else 'ruff check'
    print(f'{filename}:{row} | {category} | {severity} | {message} | {hint}')
" "$sev_map" "$raw"
}

# ---------------------------------------------------------------------------
# 1. Exits non-zero when ruff not available
# ---------------------------------------------------------------------------
@test "ruff adapter: exits non-zero when ruff not available" {
  local save_path="$PATH"
  PATH="/usr/bin:/bin"
  run bash "$ADAPTER" "/tmp" "." "$SEV_MAP"
  PATH="$save_path"
  [[ $status -eq 1 ]]
}

# ---------------------------------------------------------------------------
# 2. Parses fixture data and produces expected number of findings
# ---------------------------------------------------------------------------
@test "ruff adapter: parses 4 findings from fixture" {
  run run_parser "$SEV_MAP" "$RUFF_FIXTURE"
  assert_success
  local line_count
  line_count="$(echo "$output" | grep -c '|')"
  [[ "$line_count" -eq 4 ]]
}

# ---------------------------------------------------------------------------
# 3. F-prefixed code maps to PY-LINT-PYFLAKES category
# ---------------------------------------------------------------------------
@test "ruff adapter: F-prefix maps to PY-LINT-PYFLAKES" {
  run run_parser "$SEV_MAP" "$RUFF_FIXTURE"
  assert_success
  echo "$output" | grep "F401" | grep -q "PY-LINT-PYFLAKES"
}

# ---------------------------------------------------------------------------
# 4. S-prefixed code maps to PY-LINT-SEC and WARNING severity
# ---------------------------------------------------------------------------
@test "ruff adapter: S-prefix maps to PY-LINT-SEC with WARNING severity" {
  run run_parser "$SEV_MAP" "$RUFF_FIXTURE"
  assert_success
  echo "$output" | grep "S101" | grep -q "PY-LINT-SEC | WARNING"
}

# ---------------------------------------------------------------------------
# 5. E-prefixed code maps to PY-LINT-STYLE with INFO severity
# ---------------------------------------------------------------------------
@test "ruff adapter: E-prefix maps to PY-LINT-STYLE with INFO severity" {
  run run_parser "$SEV_MAP" "$RUFF_FIXTURE"
  assert_success
  echo "$output" | grep "E501" | grep -q "PY-LINT-STYLE | INFO"
}

# ---------------------------------------------------------------------------
# 6. UP-prefixed code maps to PY-LINT-UPGRADE
# ---------------------------------------------------------------------------
@test "ruff adapter: UP-prefix maps to PY-LINT-UPGRADE" {
  run run_parser "$SEV_MAP" "$RUFF_FIXTURE"
  assert_success
  echo "$output" | grep "UP006" | grep -q "PY-LINT-UPGRADE"
}

# ---------------------------------------------------------------------------
# 7. File paths and line numbers are preserved
# ---------------------------------------------------------------------------
@test "ruff adapter: preserves file:line format" {
  run run_parser "$SEV_MAP" "$RUFF_FIXTURE"
  assert_success
  echo "$output" | grep -q "src/main.py:3"
  echo "$output" | grep -q "src/auth.py:15"
  echo "$output" | grep -q "src/utils.py:42"
}

# ---------------------------------------------------------------------------
# 8. Hint includes ruff rule code
# ---------------------------------------------------------------------------
@test "ruff adapter: hint includes ruff rule code" {
  run run_parser "$SEV_MAP" "$RUFF_FIXTURE"
  assert_success
  echo "$output" | grep -q "ruff rule F401"
  echo "$output" | grep -q "ruff rule S101"
}

# ---------------------------------------------------------------------------
# 9. Empty input produces no output
# ---------------------------------------------------------------------------
@test "ruff adapter: empty input produces no output" {
  local empty_file="${TEST_TEMP}/empty.json"
  : > "$empty_file"
  run run_parser "$SEV_MAP" "$empty_file"
  assert_success
  [[ -z "$output" ]]
}

# ---------------------------------------------------------------------------
# 10. Glob prefix severity matching (longest prefix wins)
# ---------------------------------------------------------------------------
@test "ruff adapter: glob prefix severity matching uses longest match" {
  run run_parser "$SEV_MAP" "$RUFF_FIXTURE"
  assert_success
  # F401 matches F* -> WARNING (from severity map)
  echo "$output" | grep "F401" | grep -q "WARNING"
  # UP006 matches UP* -> INFO (from severity map)
  echo "$output" | grep "UP006" | grep -q "INFO"
}
