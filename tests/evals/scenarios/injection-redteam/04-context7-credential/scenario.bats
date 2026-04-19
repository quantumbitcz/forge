#!/usr/bin/env bats
# Phase 03 scenario 04: a Context7 doc snippet contains a credential-shaped
# string. The filter must quarantine it before any agent can read it.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  FIX="$BATS_TEST_DIRNAME/fixture.md"
  TMP="$(mktemp -d)"
  export PYTHONPATH="$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "scenario 04: credential-shaped — quarantine + SEC-INJECTION-BLOCKED" {
  run python3 -c "
import pathlib, sys
sys.path.insert(0, '$ROOT')
from hooks._py import mcp_response_filter as f
f.EVENTS_PATH = pathlib.Path('$TMP/e.jsonl')
r = f.filter_response(source='mcp:context7', origin='ctx7://pkg/aws',
                      content=pathlib.Path('$FIX').read_text(),
                      run_id='sc04', agent='fg-140-deprecation-refresh')
assert r['action'] == 'quarantine', r
assert r['envelope'] is None
assert any(x['severity'] == 'BLOCK' for x in r['findings'])
print('ok')
"
  [ "$status" -eq 0 ]
}
