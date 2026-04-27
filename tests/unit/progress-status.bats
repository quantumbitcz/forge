#!/usr/bin/env bats
# AC-11: hooks/_py/progress.py writes .forge/progress/status.json atomically.
load '../helpers/test-helpers'

setup() {
  TMP="$(mktemp -d)"
  cd "$TMP"
  mkdir -p .forge
  printf '%s\n' \
    '{"schema":1,"run_id":"R-1","stage":"PLANNING","stage_entered_at":"2026-04-22T10:00:00Z","stage_timeout_ms":600000}' \
    > .forge/state.json
  printf '%s\n' \
    '{"ts":"2026-04-22T10:00:05Z","type":"agent_dispatch","run_id":"R-1","stage":"PLANNING","agent":"fg-200-planner","detail":"fg-200 started"}' \
    > .forge/events.jsonl
}

teardown() {
  rm -rf "$TMP"
}

@test "write_status_from_hook creates status.json with required fields" {
  run python3 -c "
import sys
sys.path.insert(0,'$PLUGIN_ROOT/hooks')
from _py.progress import write_status_from_hook
write_status_from_hook(cwd='$TMP')
"
  assert_success
  assert [ -f "$TMP/.forge/progress/status.json" ]
  run python3 -c "
import json
d = json.load(open('$TMP/.forge/progress/status.json'))
for k in ('run_id','stage','agent_active','elapsed_ms_in_stage','timeout_ms','last_event','updated_at','writer'):
    assert k in d, k
assert d['writer'] == 'post_tool_use_agent.py'
assert d['stage'] == 'PLANNING'
assert d['run_id'] == 'R-1'
"
  assert_success
}

@test "write_status uses atomic os.replace (no .tmp leftover)" {
  python3 -c "
import sys
sys.path.insert(0,'$PLUGIN_ROOT/hooks')
from _py.progress import write_status_from_hook
write_status_from_hook(cwd='$TMP')
"
  refute [ -f "$TMP/.forge/progress/status.json.tmp" ]
}

@test "write_status is a no-op when .forge missing" {
  rm -rf "$TMP/.forge"
  run python3 -c "
import sys
sys.path.insert(0,'$PLUGIN_ROOT/hooks')
from _py.progress import write_status_from_hook
write_status_from_hook(cwd='$TMP')
"
  assert_success
  refute [ -d "$TMP/.forge/progress" ]
}

@test "write_status is a no-op when run_id is absent (idle, not 'unknown')" {
  printf '%s\n' '{"schema":1,"stage":"PLANNING"}' > "$TMP/.forge/state.json"
  : > "$TMP/.forge/events.jsonl"
  run python3 -c "
import sys
sys.path.insert(0,'$PLUGIN_ROOT/hooks')
from _py.progress import write_status_from_hook
write_status_from_hook(cwd='$TMP')
"
  assert_success
  refute [ -f "$TMP/.forge/progress/status.json" ]
}
