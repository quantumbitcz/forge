#!/usr/bin/env bats
# Phase 03 scenario 01: hostile wiki page tries to override agent instructions.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  FIX="$BATS_TEST_DIRNAME/fixture.md"
  TMP="$(mktemp -d)"
  export PYTHONPATH="$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "scenario 01: wiki override — OVERRIDE + SYSTEM_SPOOF reported, content wrapped" {
  run python3 -c "
import json, pathlib, os, sys
sys.path.insert(0, '$ROOT')
from hooks._py import mcp_response_filter as f
f.EVENTS_PATH = pathlib.Path('$TMP/events.jsonl')
content = pathlib.Path('$FIX').read_text()
r = f.filter_response(source='wiki', origin='$FIX',
                      content=content, run_id='sc01',
                      agent='fg-020-bug-investigator')
assert r['action'] == 'wrap', r
cats = {x['category'] for x in r['findings']}
assert 'OVERRIDE' in cats, cats
assert 'SYSTEM_SPOOF' in cats, cats
assert 'flags=\"' in r['envelope']
print('ok')
"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}
