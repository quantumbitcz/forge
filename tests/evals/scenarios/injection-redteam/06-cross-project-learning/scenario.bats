#!/usr/bin/env bats
# Phase 03 scenario 06: a cross-project learning import carries a hostile
# override directive.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  FIX="$BATS_TEST_DIRNAME/fixture.md"
  TMP="$(mktemp -d)"
  export PYTHONPATH="$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "scenario 06: cross-project learning — OVERRIDE WARNING logged" {
  run python3 -c "
import pathlib, sys
sys.path.insert(0, '$ROOT')
from hooks._py import mcp_response_filter as f
f.EVENTS_PATH = pathlib.Path('$TMP/e.jsonl')
r = f.filter_response(source='cross-project-learnings', origin='learnings://acme',
                      content=pathlib.Path('$FIX').read_text(),
                      run_id='sc06', agent='fg-100-orchestrator')
assert r['action'] == 'wrap'
assert any(x['category'] == 'OVERRIDE' and x['severity'] == 'WARNING' for x in r['findings'])
print('ok')
"
  [ "$status" -eq 0 ]
}
