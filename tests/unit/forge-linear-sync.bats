#!/usr/bin/env bats
# Unit tests: forge-linear-sync.sh — event-driven Linear sync.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-linear-sync.sh"
STATE_WRITER="$PLUGIN_ROOT/shared/forge-state-write.sh"

@test "forge-linear-sync: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-linear-sync: emit writes event to linear-events.jsonl" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"integrations":{"linear":{"available":false}}}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" emit plan_complete '{"epic_title":"Test"}' --forge-dir "$forge_dir"
  assert_success
  assert [ -f "$forge_dir/linear-events.jsonl" ]

  python3 - "$forge_dir/linear-events.jsonl" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    line = f.readline().strip()
    d = json.loads(line)
    assert d['event_type'] == 'plan_complete'
    assert d['linear_available'] == False
PYEOF
}

@test "forge-linear-sync: emit always exits 0 even with bad JSON" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"integrations":{"linear":{"available":false}}}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" emit plan_complete 'not-json' --forge-dir "$forge_dir"
  assert_success
}

@test "forge-linear-sync: emit truncates log at 100 entries" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"integrations":{"linear":{"available":false}}}' --forge-dir "$forge_dir"

  for i in $(seq 1 105); do
    bash "$SCRIPT" emit task_started "{\"task_id\":\"t-$i\"}" --forge-dir "$forge_dir"
  done

  local line_count
  line_count=$(wc -l < "$forge_dir/linear-events.jsonl" | tr -d ' ')
  assert [ "$line_count" -le 100 ]
}

@test "forge-linear-sync: emit records linear_available status" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"integrations":{"linear":{"available":true,"team":"TEST"}}}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" emit pr_created '{"epic_id":"E1","pr_url":"https://github.com/test/pr/1"}' --forge-dir "$forge_dir"
  assert_success

  python3 - "$forge_dir/linear-events.jsonl" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.loads(f.readline().strip())
    assert d['linear_available'] == True
PYEOF
}

@test "forge-linear-sync: emit works without state.json (exits 0)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" emit task_completed '{"task_id":"t1"}' --forge-dir "$forge_dir"
  assert_success
}
