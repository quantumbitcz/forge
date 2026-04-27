#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export TMPDIR="$(mktemp -d)"
  export STATE="$TMPDIR/state.json"
  python3 -c "
import sys, json, pathlib
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from state_init import create_initial_state
pathlib.Path('$STATE').write_text(json.dumps(create_initial_state('test-1', 'req', 'standard', False), indent=2))
"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "create_initial_state creates state with version 2.0.0 and zeroed judge counters" {
  run python3 -c "
import json
s=json.load(open('$STATE'))
assert s['version'] == '2.0.0', s['version']
assert s['plan_judge_loops'] == 0
assert s['impl_judge_loops'] == {}
assert s['judge_verdicts'] == []
print('OK')
"
  [ "$status" -eq 0 ]
}

@test "1st REVISE increments plan_judge_loops to 1" {
  run python3 -c "
import json, sys
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from judge_plumbing import record_plan_judge_verdict
s = json.load(open('$STATE'))
s = record_plan_judge_verdict(s, verdict='REVISE', dispatch_seq=1, timestamp='2026-04-22T10:00:00Z')
assert s['plan_judge_loops'] == 1, s['plan_judge_loops']
assert len(s['judge_verdicts']) == 1
assert s['judge_verdicts'][0]['verdict'] == 'REVISE'
print('OK')
"
  [ "$status" -eq 0 ]
}

@test "2nd REVISE increments to 2, then loop-bound reached (caller reads bound)" {
  run python3 -c "
import json, sys
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from judge_plumbing import record_plan_judge_verdict, plan_judge_bound_reached
s = json.load(open('$STATE'))
s = record_plan_judge_verdict(s, verdict='REVISE', dispatch_seq=1, timestamp='2026-04-22T10:00:00Z')
s = record_plan_judge_verdict(s, verdict='REVISE', dispatch_seq=2, timestamp='2026-04-22T10:05:00Z')
assert s['plan_judge_loops'] == 2
assert plan_judge_bound_reached(s) is True
print('OK')
"
  [ "$status" -eq 0 ]
}

@test "new plan SHA resets plan_judge_loops to 0" {
  run python3 -c "
import json, sys
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from judge_plumbing import record_plan_judge_verdict, reset_plan_judge_loops_on_new_plan
s = json.load(open('$STATE'))
s['current_plan_sha'] = 'abc123'
s = record_plan_judge_verdict(s, verdict='REVISE', dispatch_seq=1, timestamp='2026-04-22T10:00:00Z')
assert s['plan_judge_loops'] == 1
s = reset_plan_judge_loops_on_new_plan(s, new_plan_sha='def456')
assert s['plan_judge_loops'] == 0
assert s['current_plan_sha'] == 'def456'
print('OK')
"
  [ "$status" -eq 0 ]
}

@test "impl_judge_loops is per-task" {
  run python3 -c "
import json, sys
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from judge_plumbing import record_impl_judge_verdict
s = json.load(open('$STATE'))
s = record_impl_judge_verdict(s, task_id='T-1', verdict='REVISE', dispatch_seq=1, timestamp='t')
s = record_impl_judge_verdict(s, task_id='T-2', verdict='PROCEED', dispatch_seq=2, timestamp='t')
assert s['impl_judge_loops'] == {'T-1': 1, 'T-2': 0}
print('OK')
"
  [ "$status" -eq 0 ]
}

@test "v1.x state file triggers auto-reset on load (no migration shim)" {
  run python3 -c "
import json, sys, pathlib
sys.path.insert(0, '$PROJECT_ROOT/shared/python')
from state_init import load_or_reinit
p = pathlib.Path('$TMPDIR/stale.json')
p.write_text(json.dumps({'version': '1.10.0', 'critic_revisions': 1}))
s = load_or_reinit(p, mode='standard')
assert s['version'] == '2.0.0', s['version']
assert 'critic_revisions' not in s
assert s['plan_judge_loops'] == 0
print('OK')
"
  [ "$status" -eq 0 ]
}
