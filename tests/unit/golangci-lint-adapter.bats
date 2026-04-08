#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/golangci-lint.sh

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/golangci-lint.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
GL_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/golangci-lint-sample.json"

# ---------------------------------------------------------------------------
# Python parser extracted from golangci-lint.sh
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
gl_map = full_map.get('golangci-lint', {})

def lookup_severity(linter, text):
    if linter and linter in gl_map:
        return gl_map[linter]
    t = (text or '').lower()
    if any(w in t for w in ('error', 'undefined', 'cannot', 'illegal')):
        return 'CRITICAL'
    if any(w in t for w in ('should', 'consider', 'unused', 'shadow')):
        return 'WARNING'
    return 'INFO'

def map_category(linter):
    if not linter: return 'GO-LINT'
    l = linter.lower()
    if l in ('errcheck', 'errorlint'): return 'GO-LINT-ERR'
    if l in ('gosec', 'gas'): return 'GO-SEC'
    if l in ('govet', 'vet'): return 'GO-LINT-VET'
    if l in ('staticcheck', 'stylecheck'): return 'GO-LINT-SA'
    if l in ('revive', 'golint'): return 'GO-LINT-STYLE'
    if l in ('unused', 'deadcode', 'structcheck', 'varcheck'): return 'GO-LINT-UNUSED'
    if l in ('bodyclose', 'noctx'): return 'GO-LINT-PERF'
    return 'GO-LINT'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for issue in data.get('Issues') or []:
    pos = issue.get('Pos', {})
    fp = pos.get('Filename', '?')
    ln = pos.get('Line', 0)
    linter = issue.get('FromLinter', '')
    text = issue.get('Text', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
    severity = lookup_severity(linter, text)
    category = map_category(linter)
    hint = f'golangci-lint/{linter}' if linter else 'golangci-lint'
    print(f'{fp}:{ln} | {category} | {severity} | {text} | {hint}')
" "$sev_map" "$raw"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "golangci-lint adapter: exits non-zero when golangci-lint not available" {
  local save_path="$PATH"
  PATH="/usr/bin:/bin"
  run bash "$ADAPTER" "/tmp" "." "$SEV_MAP"
  PATH="$save_path"
  [[ $status -eq 1 ]]
}

@test "golangci-lint adapter: parses 4 findings from fixture" {
  run run_parser "$SEV_MAP" "$GL_FIXTURE"
  assert_success
  local line_count
  line_count="$(echo "$output" | grep -c '|')"
  [[ "$line_count" -eq 4 ]]
}

@test "golangci-lint adapter: errcheck maps to GO-LINT-ERR category" {
  run run_parser "$SEV_MAP" "$GL_FIXTURE"
  assert_success
  echo "$output" | grep "errcheck" | grep -q "GO-LINT-ERR"
}

@test "golangci-lint adapter: gosec maps to GO-SEC category" {
  run run_parser "$SEV_MAP" "$GL_FIXTURE"
  assert_success
  echo "$output" | grep "gosec" | grep -q "GO-SEC"
}

@test "golangci-lint adapter: revive maps to GO-LINT-STYLE" {
  run run_parser "$SEV_MAP" "$GL_FIXTURE"
  assert_success
  echo "$output" | grep "revive" | grep -q "GO-LINT-STYLE"
}

@test "golangci-lint adapter: unused maps to GO-LINT-UNUSED" {
  run run_parser "$SEV_MAP" "$GL_FIXTURE"
  assert_success
  echo "$output" | grep "unused" | grep -q "GO-LINT-UNUSED"
}

@test "golangci-lint adapter: file:line format preserved" {
  run run_parser "$SEV_MAP" "$GL_FIXTURE"
  assert_success
  echo "$output" | grep -q "cmd/server/main.go:42"
  echo "$output" | grep -q "internal/auth/auth.go:15"
}

@test "golangci-lint adapter: text-based severity fallback for 'should' keyword" {
  run run_parser "$SEV_MAP" "$GL_FIXTURE"
  assert_success
  # revive text contains "should" -> WARNING via text fallback
  echo "$output" | grep "revive" | grep -q "WARNING"
}

@test "golangci-lint adapter: empty input produces no output" {
  local empty_file="${TEST_TEMP}/empty.json"
  : > "$empty_file"
  run run_parser "$SEV_MAP" "$empty_file"
  assert_success
  [[ -z "$output" ]]
}

@test "golangci-lint adapter: null Issues array handled gracefully" {
  local null_file="${TEST_TEMP}/null-issues.json"
  printf '{"Issues": null}\n' > "$null_file"
  run run_parser "$SEV_MAP" "$null_file"
  assert_success
  [[ -z "$output" ]]
}
