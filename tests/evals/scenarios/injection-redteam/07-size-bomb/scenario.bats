#!/usr/bin/env bats
# Injection red-team scenario 07: a 10 MiB Figma payload tries to overflow context.
# Fixture is generated in the test (no 10 MiB blob checked in).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  TMP="$(mktemp -d)"
  export PYTHONPATH="$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "scenario 07: size-bomb — truncated + SEC-INJECTION-TRUNCATED INFO" {
  run python3 -c "
import pathlib, sys
sys.path.insert(0, '$ROOT')
from hooks._py import mcp_response_filter as f
f.EVENTS_PATH = pathlib.Path('$TMP/e.jsonl')
big = 'A' * (10 * 1024 * 1024)
r = f.filter_response(source='mcp:figma', origin='fig://file/huge',
                      content=big, run_id='sc07', agent='fg-100-orchestrator')
assert r['truncated'] is True
assert r['bytes_after_truncation'] == f.MAX_ENVELOPE_BYTES
assert any(x['id'] == 'SEC-INJECTION-TRUNCATED' for x in r['findings'])
print('ok')
"
  [ "$status" -eq 0 ]
}
