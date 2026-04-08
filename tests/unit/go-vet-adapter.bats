#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/go-vet.sh

load '../helpers/test-helpers'

SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
GOVET_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/go-vet-sample.txt"

run_parser() {
  local sev_map="$1" raw="$2"
  python3 -c "
import json, re, sys
with open(sys.argv[1]) as f: full_map = json.load(f)
sc_map = full_map.get('staticcheck', {})

def lookup_sev(code):
    if not code: return 'WARNING'
    if code in sc_map: return sc_map[code]
    best = ('', 'WARNING')
    for pat, sev in sc_map.items():
        if pat.endswith('*'):
            px = pat[:-1]
            if code.startswith(px) and len(px) > len(best[0]): best = (px, sev)
    return best[1]

CAT_PREFIX = {'SA':'GO-LINT-SA','S1':'GO-LINT-SIMPLIFY','ST':'GO-LINT-STYLE','QF':'GO-LINT-QUICKFIX'}
def map_cat(code):
    if code:
        for px, cat in CAT_PREFIX.items():
            if code.startswith(px): return cat
    return 'GO-LINT-VET'

pat_sc = re.compile(r'^(.+?):(\d+):\d+:\s+(.+?)\s+\((\w+)\)\s*$')
pat_vet = re.compile(r'^(.+?):(\d+):\d+:\s+(.+)$')
with open(sys.argv[2]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        m = pat_sc.match(line)
        if m:
            fp, ln, msg, code = m.groups()
            msg = msg.replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
            print(f'{fp}:{ln} | {map_cat(code)} | {lookup_sev(code)} | {msg} | staticcheck {code}')
            continue
        m = pat_vet.match(line)
        if m:
            fp, ln, msg = m.groups()
            msg = msg.replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
            print(f'{fp}:{ln} | GO-LINT-VET | WARNING | {msg} | go vet')
" "$sev_map" "$raw"
}

@test "go-vet adapter: parses 4 findings from fixture" {
  run run_parser "$SEV_MAP" "$GOVET_FIXTURE"
  assert_success
  local count; count="$(echo "$output" | grep -c '|')"
  [[ "$count" -eq 4 ]]
}

@test "go-vet adapter: SA code maps to GO-LINT-SA" {
  run run_parser "$SEV_MAP" "$GOVET_FIXTURE"
  assert_success
  echo "$output" | grep "SA5009" | grep -q "GO-LINT-SA"
}

@test "go-vet adapter: S1 code maps to GO-LINT-SIMPLIFY" {
  run run_parser "$SEV_MAP" "$GOVET_FIXTURE"
  assert_success
  echo "$output" | grep "S1012" | grep -q "GO-LINT-SIMPLIFY"
}

@test "go-vet adapter: ST code maps to GO-LINT-STYLE" {
  run run_parser "$SEV_MAP" "$GOVET_FIXTURE"
  assert_success
  echo "$output" | grep "ST1000" | grep -q "GO-LINT-STYLE"
}

@test "go-vet adapter: plain go vet line maps to GO-LINT-VET" {
  run run_parser "$SEV_MAP" "$GOVET_FIXTURE"
  assert_success
  echo "$output" | grep "unreachable code" | grep -q "GO-LINT-VET"
}

@test "go-vet adapter: file:line format preserved" {
  run run_parser "$SEV_MAP" "$GOVET_FIXTURE"
  assert_success
  echo "$output" | grep -q "cmd/server/main.go:42"
  echo "$output" | grep -q "internal/handler.go:30"
}

@test "go-vet adapter: empty input produces no output" {
  local empty="${TEST_TEMP}/empty.txt"
  : > "$empty"
  run run_parser "$SEV_MAP" "$empty"
  assert_success
  [[ -z "$output" ]]
}
