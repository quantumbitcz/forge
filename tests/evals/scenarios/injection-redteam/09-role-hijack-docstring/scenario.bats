#!/usr/bin/env bats
# Injection red-team scenario 09: a remote GitHub file's source comment tries to hijack
# the agent role. mcp:github:remote is T-C, so envelope is classification=confirmed.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  FIX="$BATS_TEST_DIRNAME/fixture.md"
  TMP="$(mktemp -d)"
  export PYTHONPATH="$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "scenario 09: remote-github role hijack — ROLE_HIJACK + classification=confirmed" {
  run python3 -c "
import pathlib, sys
sys.path.insert(0, '$ROOT')
from hooks._py import mcp_response_filter as f
f.EVENTS_PATH = pathlib.Path('$TMP/e.jsonl')
r = f.filter_response(source='mcp:github:remote', origin='gh://evil/repo',
                      content=pathlib.Path('$FIX').read_text(), run_id='sc09',
                      agent='fg-411-security-reviewer')
assert 'classification=\"confirmed\"' in r['envelope']
cats = {x['category'] for x in r['findings']}
assert 'ROLE_HIJACK' in cats, cats
print('ok')
"
  [ "$status" -eq 0 ]
}
