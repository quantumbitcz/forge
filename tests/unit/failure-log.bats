#!/usr/bin/env bats
# AC-5, AC-7: hooks/_py/failure_log.py — record_failure + rotate + safe-if-missing.
load '../helpers/test-helpers'

setup() {
  TMP="$(mktemp -d)"
  export FORGE_TEST_CWD="$TMP"
  cd "$TMP"
  PY="python3 -c \"import sys; sys.path.insert(0,'$PLUGIN_ROOT/hooks'); from _py import failure_log; failure_log.main()\""
}

teardown() {
  rm -rf "$TMP"
}

@test "record_failure is a no-op when .forge missing and writable is False" {
  run python3 -c "
import sys, json
sys.path.insert(0,'$PLUGIN_ROOT/hooks')
from _py import failure_log
import os
os.chdir('$TMP')
failure_log.record_failure('test.py','Edit', 1, 'oops', 42, '$TMP')
"
  assert_success
  # When .forge doesn't exist we create it (exist_ok=True per spec)
  assert [ -f "$TMP/.forge/.hook-failures.jsonl" ]
}

@test "record_failure appends a valid JSON row" {
  mkdir -p "$TMP/.forge"
  python3 -c "
import sys, os
sys.path.insert(0,'$PLUGIN_ROOT/hooks')
os.chdir('$TMP')
from _py import failure_log
failure_log.record_failure('pre_tool_use.py','Edit|Write',2,'boom',1,'$TMP')
"
  run python3 -c "
import json
with open('$TMP/.forge/.hook-failures.jsonl') as f:
    row = json.loads(f.readline())
assert row['schema'] == 1
assert row['hook_name'] == 'pre_tool_use.py'
assert row['exit_code'] == 2
assert row['duration_ms'] == 1
assert 'ts' in row and row['ts'].endswith('Z')
"
  assert_success
}

@test "record_failure truncates stderr_excerpt to 2048 bytes" {
  mkdir -p "$TMP/.forge"
  python3 -c "
import sys, os
sys.path.insert(0,'$PLUGIN_ROOT/hooks')
os.chdir('$TMP')
from _py import failure_log
failure_log.record_failure('h.py','m',1,'x'*5000,10,'$TMP')
"
  run python3 -c "
import json
row = json.loads(open('$TMP/.forge/.hook-failures.jsonl').readline())
assert len(row['stderr_excerpt']) == 2048
"
  assert_success
}

@test "rotate gzips files older than 7 days" {
  mkdir -p "$TMP/.forge"
  touch -t 202601010000 "$TMP/.forge/.hook-failures.jsonl"
  printf '{"schema":1,"ts":"2026-01-01T00:00:00Z","hook_name":"x","matcher":"m","exit_code":1,"duration_ms":1,"cwd":"."}\n' > "$TMP/.forge/.hook-failures.jsonl"
  touch -t 202601010000 "$TMP/.forge/.hook-failures.jsonl"
  python3 -c "
import sys, os
sys.path.insert(0,'$PLUGIN_ROOT/hooks')
os.chdir('$TMP')
from _py import failure_log
failure_log.rotate(now_ts=None)
"
  run bash -c "ls '$TMP/.forge/'"
  assert_success
  refute_output --partial '.hook-failures.jsonl'
  assert_output --regexp '\.hook-failures-[0-9]{8}\.jsonl\.gz'
}

@test "rotate deletes gz older than 30 days" {
  mkdir -p "$TMP/.forge"
  old="$TMP/.forge/.hook-failures-20250101.jsonl.gz"
  printf 'x' | gzip -c > "$old"
  touch -t 202501010000 "$old"
  python3 -c "
import sys, os
sys.path.insert(0,'$PLUGIN_ROOT/hooks')
os.chdir('$TMP')
from _py import failure_log
failure_log.rotate(now_ts=None)
"
  refute [ -f "$old" ]
}
