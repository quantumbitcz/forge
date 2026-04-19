#!/usr/bin/env bats
# Phase 03 scenario 03: Playwright snapshot of a hostile page tries to coerce shell.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  FIX="$BATS_TEST_DIRNAME/fixture.md"
  TMP="$(mktemp -d)"
  export PYTHONPATH="$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "scenario 03: playwright coercion — TOOL_COERCION flagged + classification=confirmed" {
  run python3 -c "
import pathlib, sys
sys.path.insert(0, '$ROOT')
from hooks._py import mcp_response_filter as f
f.EVENTS_PATH = pathlib.Path('$TMP/e.jsonl')
r = f.filter_response(source='mcp:playwright', origin='page://x',
                      content=pathlib.Path('$FIX').read_text(),
                      run_id='sc03', agent='fg-020-bug-investigator')
assert r['action'] == 'wrap', r
assert 'classification=\"confirmed\"' in r['envelope']
cats = {x['category'] for x in r['findings']}
assert 'TOOL_COERCION' in cats, cats
print('ok')
"
  [ "$status" -eq 0 ]
}
