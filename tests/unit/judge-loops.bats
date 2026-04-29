#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # Convert MSYS path to mixed form on native Windows (Git Bash); native Python
  # cannot resolve /d/a/forge/forge but accepts D:/a/forge/forge.
  if command -v cygpath >/dev/null 2>&1; then
    PROJECT_ROOT="$(cygpath -m "$PROJECT_ROOT")"
  fi
  export TMPDIR="$(mktemp -d)"
  if command -v cygpath >/dev/null 2>&1; then
    TMPDIR="$(cygpath -m "$TMPDIR")"
    export TMPDIR
  fi
  export STATE="$TMPDIR/state.json"
  python3 - "$PROJECT_ROOT/shared/python" "$STATE" <<'PYEOF'
import sys, json, pathlib
sys.path.insert(0, sys.argv[1])
from state_init import create_initial_state
pathlib.Path(sys.argv[2]).write_text(json.dumps(create_initial_state('test-1', 'req', 'standard', False), indent=2))
PYEOF
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "create_initial_state creates state with version 2.1.0 and zeroed judge counters" {
  run python3 - "$STATE" <<'PYEOF'
import json, sys
s=json.load(open(sys.argv[1]))
assert s['version'] == '2.1.0', s['version']
assert s['plan_judge_loops'] == 0
assert s['impl_judge_loops'] == {}
assert s['judge_verdicts'] == []
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}

@test "1st REVISE increments plan_judge_loops to 1" {
  run python3 - "$PROJECT_ROOT/shared/python" "$STATE" <<'PYEOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from judge_plumbing import record_plan_judge_verdict
s = json.load(open(sys.argv[2]))
s = record_plan_judge_verdict(s, verdict='REVISE', dispatch_seq=1, timestamp='2026-04-22T10:00:00Z')
assert s['plan_judge_loops'] == 1, s['plan_judge_loops']
assert len(s['judge_verdicts']) == 1
assert s['judge_verdicts'][0]['verdict'] == 'REVISE'
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}

@test "2nd REVISE increments to 2, then loop-bound reached (caller reads bound)" {
  run python3 - "$PROJECT_ROOT/shared/python" "$STATE" <<'PYEOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from judge_plumbing import record_plan_judge_verdict, plan_judge_bound_reached
s = json.load(open(sys.argv[2]))
s = record_plan_judge_verdict(s, verdict='REVISE', dispatch_seq=1, timestamp='2026-04-22T10:00:00Z')
s = record_plan_judge_verdict(s, verdict='REVISE', dispatch_seq=2, timestamp='2026-04-22T10:05:00Z')
assert s['plan_judge_loops'] == 2
assert plan_judge_bound_reached(s) is True
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}

@test "new plan SHA resets plan_judge_loops to 0" {
  run python3 - "$PROJECT_ROOT/shared/python" "$STATE" <<'PYEOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from judge_plumbing import record_plan_judge_verdict, reset_plan_judge_loops_on_new_plan
s = json.load(open(sys.argv[2]))
s['current_plan_sha'] = 'abc123'
s = record_plan_judge_verdict(s, verdict='REVISE', dispatch_seq=1, timestamp='2026-04-22T10:00:00Z')
assert s['plan_judge_loops'] == 1
s = reset_plan_judge_loops_on_new_plan(s, new_plan_sha='def456')
assert s['plan_judge_loops'] == 0
assert s['current_plan_sha'] == 'def456'
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}

@test "impl_judge_loops is per-task" {
  run python3 - "$PROJECT_ROOT/shared/python" "$STATE" <<'PYEOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from judge_plumbing import record_impl_judge_verdict
s = json.load(open(sys.argv[2]))
s = record_impl_judge_verdict(s, task_id='T-1', verdict='REVISE', dispatch_seq=1, timestamp='t')
s = record_impl_judge_verdict(s, task_id='T-2', verdict='PROCEED', dispatch_seq=2, timestamp='t')
assert s['impl_judge_loops'] == {'T-1': 1, 'T-2': 0}
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}

@test "v1.x state file triggers auto-reset on load (no migration shim)" {
  run python3 - "$PROJECT_ROOT/shared/python" "$TMPDIR/stale.json" <<'PYEOF'
import json, sys, pathlib
sys.path.insert(0, sys.argv[1])
from state_init import load_or_reinit
p = pathlib.Path(sys.argv[2])
p.write_text(json.dumps({'version': '1.10.0', 'critic_revisions': 1}))
s = load_or_reinit(p, mode='standard')
assert s['version'] == '2.1.0', s['version']
assert 'critic_revisions' not in s
assert s['plan_judge_loops'] == 0
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}

@test "corrupted state.json (malformed JSON) reinits without crash" {
  run python3 - "$PROJECT_ROOT/shared/python" "$TMPDIR/corrupt.json" <<'PYEOF'
import sys, pathlib
sys.path.insert(0, sys.argv[1])
from state_init import load_or_reinit
p = pathlib.Path(sys.argv[2])
# Write malformed JSON: truncated, unterminated string, garbage
p.write_text('{"version": "2.1.0", "plan_judge_loops": 1, "unterminated": "this string never')
s = load_or_reinit(p, mode='standard')
assert s['version'] == '2.1.0', s['version']
assert s['plan_judge_loops'] == 0, s['plan_judge_loops']
assert s['judge_verdicts'] == []
# Backup of corrupt file should exist alongside the reinit
backup = p.parent / 'state.v1.bak'
assert backup.exists(), 'expected corrupt-file backup at state.v1.bak'
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}

@test "future-version state.json (3.0.0) reinits with version_mismatch (treated as unknown)" {
  run python3 - "$PROJECT_ROOT/shared/python" "$TMPDIR/future.json" <<'PYEOF'
import json, sys, pathlib
sys.path.insert(0, sys.argv[1])
from state_init import load_or_reinit
p = pathlib.Path(sys.argv[2])
p.write_text(json.dumps({'version': '3.0.0', 'some_future_field': 'xyz', 'plan_judge_loops': 99}))
s = load_or_reinit(p, mode='standard')
assert s['version'] == '2.1.0', s['version']
# Future field is dropped (no migration shim, treated as unknown)
assert 'some_future_field' not in s
assert s['plan_judge_loops'] == 0, s['plan_judge_loops']
# Backup of the unknown-version file should exist
backup = p.parent / 'state.v1.bak'
assert backup.exists(), 'expected version_mismatch backup at state.v1.bak'
backup_data = json.loads(backup.read_text())
assert backup_data['version'] == '3.0.0', backup_data['version']
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}
