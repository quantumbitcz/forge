#!/usr/bin/env bats
# Injection red-team scenario 02: Linear ticket asks the agent to exfil the system prompt.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  FIX="$BATS_TEST_DIRNAME/fixture.md"
  TMP="$(mktemp -d)"
  export PYTHONPATH="$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "scenario 02: linear exfil — SEC-INJECTION-EXFIL CRITICAL flagged" {
  run python3 -c "
import pathlib, sys
sys.path.insert(0, '$ROOT')
from hooks._py import mcp_response_filter as f
f.EVENTS_PATH = pathlib.Path('$TMP/e.jsonl')
r = f.filter_response(source='mcp:linear', origin='linear://ACME-1234',
                      content=pathlib.Path('$FIX').read_text(),
                      run_id='sc02', agent='fg-020-bug-investigator')
assert r['action'] == 'wrap', r
sev_by_cat = {x['category']: x['severity'] for x in r['findings']}
assert sev_by_cat.get('EXFIL') == 'CRITICAL', sev_by_cat
print('ok')
"
  [ "$status" -eq 0 ]
}
