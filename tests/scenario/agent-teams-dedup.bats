#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # PYTHONPATH covers shared/python so `import findings_store` works on Windows
  # (Git Bash), where MSYS-style sys.path entries cannot be resolved by native
  # Python; MSYS auto-converts known path-style env vars across the boundary.
  export PYTHONPATH="$PROJECT_ROOT/shared/python${PYTHONPATH:+:$PYTHONPATH}"
  export TMPDIR="$(mktemp -d)"
  export RUNS="$TMPDIR/.forge/runs/R/findings"
  mkdir -p "$RUNS"
}

teardown() { rm -rf "$TMPDIR"; }

@test "3 reviewers with overlapping findings → one scored entry + non-empty seen_by" {
  # Simulate 3 reviewers emitting findings with the same dedup_key
  python3 -c "
import sys, pathlib
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from findings_store import append_finding, reduce_findings
root = pathlib.Path('$RUNS')
for i, (reviewer, sev, conf) in enumerate([
  ('fg-410-code-reviewer', 'INFO', 'LOW'),
  ('fg-411-security-reviewer', 'CRITICAL', 'HIGH'),
  ('fg-412-architecture-reviewer', 'WARNING', 'MEDIUM'),
]):
  append_finding(root, reviewer, {
    'finding_id': f'f-{reviewer}-01J2BQK000{i}',
    'dedup_key': 'src/Controller.kt:42:SEC-AUTH-003',
    'reviewer': reviewer,
    'severity': sev,
    'category': 'SEC-AUTH-003',
    'file': 'src/Controller.kt', 'line': 42,
    'message': 'Missing ownership check',
    'confidence': conf,
    'created_at': f'2026-04-22T10:00:0{i}Z',
    'seen_by': []
  })

out = reduce_findings(root, writer_glob='fg-4*.jsonl')
assert len(out) == 1, out
winner = out[0]
assert winner['severity'] == 'CRITICAL', winner['severity']  # highest sev
assert winner['reviewer'] == 'fg-411-security-reviewer'
assert set(winner['seen_by']) == {'fg-410-code-reviewer', 'fg-412-architecture-reviewer'}
print('OK')
"
}

@test "Phase 7 tolerance: fg-540 INTENT finding with null file/line reduces correctly" {
  python3 -c "
import sys, pathlib
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from findings_store import append_finding, reduce_findings
root = pathlib.Path('$RUNS')
append_finding(root, 'fg-540-intent-verifier', {
  'finding_id': 'f-fg-540-intent-verifier-01J2BQK000Z',
  'dedup_key': '-:-:INTENT-AC-007',
  'reviewer': 'fg-540-intent-verifier',
  'severity': 'WARNING',
  'category': 'INTENT-AC-007',
  'file': None, 'line': None,
  'ac_id': 'AC-007',
  'message': 'AC-007 has no assertion coverage',
  'confidence': 'HIGH',
  'created_at': '2026-04-22T10:10:00Z',
  'seen_by': []
})
# Aggregator reads ONLY fg-4* by contract; fg-540 is reduced by a different consumer
out_phase5 = reduce_findings(root, writer_glob='fg-4*.jsonl')
out_phase7 = reduce_findings(root, writer_glob='fg-540*.jsonl')
assert out_phase5 == []
assert len(out_phase7) == 1 and out_phase7[0]['ac_id'] == 'AC-007'
print('OK')
"
}
