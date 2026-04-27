#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "append_finding writes a line and read_peers excludes self" {
  run python3 -c "
import sys, pathlib, json
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from findings_store import append_finding, read_peers
root = pathlib.Path('$TMPDIR/.forge/runs/R/findings')
append_finding(root, 'fg-410-code-reviewer', {
  'finding_id': 'f-fg-410-code-reviewer-01J2BQK0000',
  'dedup_key': 'a.kt:1:QUAL-NAME',
  'reviewer': 'fg-410-code-reviewer',
  'severity': 'INFO',
  'category': 'QUAL-NAME',
  'file': 'a.kt',
  'line': 1,
  'message': 'name',
  'confidence': 'LOW',
  'created_at': '2026-04-22T10:00:00Z',
  'seen_by': []
})
append_finding(root, 'fg-411-security-reviewer', {
  'finding_id': 'f-fg-411-security-reviewer-01J2BQK0001',
  'dedup_key': 'a.kt:1:SEC-INJ',
  'reviewer': 'fg-411-security-reviewer',
  'severity': 'CRITICAL',
  'category': 'SEC-INJ',
  'file': 'a.kt',
  'line': 1,
  'message': 'inj',
  'confidence': 'HIGH',
  'created_at': '2026-04-22T10:00:01Z',
  'seen_by': []
})
peers = list(read_peers(root, exclude_reviewer='fg-410-code-reviewer'))
assert len(peers) == 1, peers
assert peers[0]['reviewer'] == 'fg-411-security-reviewer'
print('OK')
"
  [ "$status" -eq 0 ]
}

@test "reduce_findings collapses duplicates and merges seen_by" {
  run python3 -c "
import sys, pathlib
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from findings_store import append_finding, reduce_findings
root = pathlib.Path('$TMPDIR/.forge/runs/R/findings')
for i, reviewer in enumerate(['fg-410-code-reviewer', 'fg-412-architecture-reviewer']):
    append_finding(root, reviewer, {
      'finding_id': f'f-{reviewer}-01J2BQK000{i}',
      'dedup_key': 'x.kt:5:ARCH-LAYER',
      'reviewer': reviewer,
      'severity': ['INFO','WARNING'][i],
      'category': 'ARCH-LAYER',
      'file': 'x.kt', 'line': 5,
      'message': 'layer',
      'confidence': 'MEDIUM',
      'created_at': f'2026-04-22T10:00:0{i}Z',
      'seen_by': []
    })
out = reduce_findings(root, writer_glob='fg-4*.jsonl')
assert len(out) == 1, out
assert out[0]['severity'] == 'WARNING'  # higher severity wins
assert 'fg-410-code-reviewer' in out[0]['seen_by'] or 'fg-412-architecture-reviewer' in out[0]['seen_by']
print('OK')
"
  [ "$status" -eq 0 ]
}

@test "reduce_findings skips malformed JSON lines with warning" {
  run python3 -c "
import sys, pathlib, io, contextlib
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from findings_store import reduce_findings
root = pathlib.Path('$TMPDIR/.forge/runs/R/findings')
root.mkdir(parents=True)
(root / 'fg-410-code-reviewer.jsonl').write_text('{not json}\n')
buf = io.StringIO()
with contextlib.redirect_stderr(buf):
    out = reduce_findings(root, writer_glob='fg-4*.jsonl')
assert out == []
assert 'fg-410-code-reviewer' in buf.getvalue() and 'line 1' in buf.getvalue()
print('OK')
"
  [ "$status" -eq 0 ]
}
