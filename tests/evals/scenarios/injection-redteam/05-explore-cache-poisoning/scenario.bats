#!/usr/bin/env bats
# Phase 03 scenario 05: a previous session's explore-cache contains a hostile
# summary (cache file written by a malicious read).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  FIX="$BATS_TEST_DIRNAME/fixture.md"
  TMP="$(mktemp -d)"
  export PYTHONPATH="$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "scenario 05: cache poisoning — ROLE_HIJACK + SYSTEM_SPOOF flagged" {
  run python3 -c "
import pathlib, sys
sys.path.insert(0, '$ROOT')
from hooks._py import mcp_response_filter as f
f.EVENTS_PATH = pathlib.Path('$TMP/e.jsonl')
r = f.filter_response(source='explore-cache', origin='.forge/explore-cache.json',
                      content=pathlib.Path('$FIX').read_text(),
                      run_id='sc05', agent='fg-100-orchestrator')
assert r['action'] == 'wrap'
cats = {x['category'] for x in r['findings']}
assert {'ROLE_HIJACK', 'SYSTEM_SPOOF'}.issubset(cats), cats
print('ok')
"
  [ "$status" -eq 0 ]
}
