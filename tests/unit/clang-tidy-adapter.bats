#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/clang-tidy.sh

load '../helpers/test-helpers'

SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
CT_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/clang-tidy-sample.txt"

run_parser() {
  local sev_map="$1" raw="$2"
  python3 -c "
import json, re, sys
with open(sys.argv[1]) as f: full_map = json.load(f)
ct_map = full_map.get('clang-tidy', {})

def lookup_sev(check, diag_sev):
    best = ('', None)
    for pat, sev in ct_map.items():
        if pat.endswith('*'):
            px = pat[:-1]
            if check.startswith(px) and len(px) > len(best[0]): best = (px, sev)
    return best[1] if best[1] else ct_map.get(diag_sev, 'INFO')

CAT_PREFIX = {'bugprone':'C-LINT-BUGPRONE','cert':'C-LINT-CERT','security':'C-LINT-SECURITY',
              'modernize':'C-LINT-MODERNIZE','performance':'C-LINT-PERF','readability':'C-LINT-READABILITY'}
def map_cat(check):
    for px, cat in CAT_PREFIX.items():
        if check.startswith(px): return cat
    return 'C-LINT-TIDY'

pat = re.compile(r'^(.+?):(\d+):\d+:\s+(warning|error|note):\s+(.+?)\s+\[([^\]]+)\]\s*$')
with open(sys.argv[2]) as f:
    for line in f:
        m = pat.match(line.strip())
        if not m: continue
        fp, ln, diag_sev, msg, check = m.groups()
        if diag_sev == 'note': continue
        msg = msg.replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
        print(f'{fp}:{ln} | {map_cat(check)} | {lookup_sev(check, diag_sev)} | {msg} | clang-tidy [{check}]')
" "$sev_map" "$raw"
}

@test "clang-tidy adapter: parses 3 findings (skips note)" {
  run run_parser "$SEV_MAP" "$CT_FIXTURE"
  assert_success
  local count; count="$(echo "$output" | grep -c '|')"
  [[ "$count" -eq 3 ]]
}

@test "clang-tidy adapter: bugprone check maps to C-LINT-BUGPRONE" {
  run run_parser "$SEV_MAP" "$CT_FIXTURE"
  assert_success
  echo "$output" | grep "bugprone-signed-bitwise" | grep -q "C-LINT-BUGPRONE"
}

@test "clang-tidy adapter: cert check maps to C-LINT-CERT" {
  run run_parser "$SEV_MAP" "$CT_FIXTURE"
  assert_success
  echo "$output" | grep "cert-arr39-c" | grep -q "C-LINT-CERT"
}

@test "clang-tidy adapter: modernize check maps to C-LINT-MODERNIZE" {
  run run_parser "$SEV_MAP" "$CT_FIXTURE"
  assert_success
  echo "$output" | grep "modernize-use-nullptr" | grep -q "C-LINT-MODERNIZE"
}

@test "clang-tidy adapter: file:line format preserved" {
  run run_parser "$SEV_MAP" "$CT_FIXTURE"
  assert_success
  echo "$output" | grep -q "src/main.c:15"
  echo "$output" | grep -q "src/auth.c:42"
}

@test "clang-tidy adapter: empty input produces no output" {
  local empty="${TEST_TEMP}/empty.txt"
  : > "$empty"
  run run_parser "$SEV_MAP" "$empty"
  assert_success
  [[ -z "$output" ]]
}
