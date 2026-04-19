#!/usr/bin/env bats
# Phase 03 scenario 08: hostile content tries to escape its envelope by closing
# the </untrusted> tag and opening a fake <instructions> block. Filter must
# neutralize the close tag with a zero-width joiner.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  FIX="$BATS_TEST_DIRNAME/fixture.md"
  TMP="$(mktemp -d)"
  export PYTHONPATH="$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "scenario 08: nested envelope — zero-width-joiner applied, exactly one close tag" {
  run python3 -c "
import pathlib, re, sys
sys.path.insert(0, '$ROOT')
from hooks._py import mcp_response_filter as f
f.EVENTS_PATH = pathlib.Path('$TMP/e.jsonl')
content = pathlib.Path('$FIX').read_text()
r = f.filter_response(source='mcp:linear', origin='linear://ACME-2099',
                      content=content, run_id='sc08',
                      agent='fg-020-bug-investigator')
assert r['action'] == 'wrap'
assert '</untrusted\u200B>' in r['envelope']
close_tags = re.findall(r'</untrusted>', r['envelope'])
assert len(close_tags) == 1, f'expected 1 close tag, got {len(close_tags)}'
print('ok')
"
  [ "$status" -eq 0 ]
}
