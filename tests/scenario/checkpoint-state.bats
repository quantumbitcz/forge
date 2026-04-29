#!/usr/bin/env bats
# Scenario tests: hooks/post_tool_use_skill.py (Python checkpoint hook).
#
# The Python port writes JSONL entries to .forge/checkpoints.jsonl instead of
# mutating state.json.lastCheckpoint. These tests cover the observable
# persistence behavior.

# Covers:

load '../helpers/test-helpers'

CHECKPOINT_HOOK="$PLUGIN_ROOT/hooks/post_tool_use_skill.py"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-checkpoint.XXXXXX")"
  MOCK_BIN="$TEST_TEMP/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
  mkdir -p "$TEST_TEMP/project/.forge"
}

teardown() { rm -rf "$TEST_TEMP"; }

# ---------------------------------------------------------------------------
# 1. .forge exists → checkpoints.jsonl is created and appended to
# ---------------------------------------------------------------------------
@test "checkpoint: creates checkpoints.jsonl with expected fields" {
  local proj="$TEST_TEMP/project"
  local log="$proj/.forge/checkpoints.jsonl"

  run bash -c "cd '$proj' && echo '{\"tool_name\":\"Skill\",\"tool_input\":{\"skill_name\":\"forge-run\"}}' | python3 '$CHECKPOINT_HOOK'"
  assert_success
  assert [ -f "$log" ]
  # Verify fields
  run python3 - "$log" <<'PY'
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as f:
    line = f.readline().strip()
entry = json.loads(line)
for key in ('timestamp', 'skill', 'tool'):
    assert key in entry, f'missing {key}'
assert entry['skill'] == 'forge-run'
assert entry['tool'] == 'Skill'
PY
  assert_success
}

# ---------------------------------------------------------------------------
# 2. Successive invocations append (do not overwrite)
# ---------------------------------------------------------------------------
@test "checkpoint: successive invocations append new lines" {
  local proj="$TEST_TEMP/project"
  local log="$proj/.forge/checkpoints.jsonl"

  run bash -c "cd '$proj' && echo '{\"tool_input\":{\"skill_name\":\"one\"}}' | python3 '$CHECKPOINT_HOOK'"
  assert_success
  run bash -c "cd '$proj' && echo '{\"tool_input\":{\"skill_name\":\"two\"}}' | python3 '$CHECKPOINT_HOOK'"
  assert_success

  local count
  count=$(wc -l < "$log" | tr -d ' ')
  [[ "$count" = "2" ]] || fail "expected 2 lines, got $count"
}

# ---------------------------------------------------------------------------
# 3. Missing .forge → no-op (exit 0)
# ---------------------------------------------------------------------------
@test "checkpoint: missing .forge causes script to exit 0 cleanly" {
  local proj="$TEST_TEMP/project"
  rm -rf "$proj/.forge"

  run bash -c "cd '$proj' && echo '{}' | python3 '$CHECKPOINT_HOOK'"
  assert_success
  assert [ ! -d "$proj/.forge" ]
}

# ---------------------------------------------------------------------------
# 4. Malformed stdin JSON → exit 0, no file created
# ---------------------------------------------------------------------------
@test "checkpoint: malformed stdin JSON causes exit 0 without writing" {
  local proj="$TEST_TEMP/project"
  local log="$proj/.forge/checkpoints.jsonl"

  run bash -c "cd '$proj' && echo 'NOT VALID JSON {' | python3 '$CHECKPOINT_HOOK'"
  assert_success
  assert [ ! -f "$log" ]
}

# ---------------------------------------------------------------------------
# 5. Timestamp is ISO 8601 UTC (RFC 3339 with timezone offset)
# ---------------------------------------------------------------------------
@test "checkpoint: timestamp is ISO 8601 UTC" {
  local proj="$TEST_TEMP/project"
  local log="$proj/.forge/checkpoints.jsonl"

  run bash -c "cd '$proj' && echo '{\"tool_input\":{\"skill_name\":\"x\"}}' | python3 '$CHECKPOINT_HOOK'"
  assert_success

  run python3 - "$log" <<'PY'
import json
import re
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as f:
    entry = json.loads(f.readline())
ts = entry.get('timestamp', '')
# Accept RFC 3339 / ISO-8601 with timezone offset (e.g. 2026-04-19T12:34:56.789+00:00 or Z)
pat = r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$'
if not re.match(pat, ts):
    print(f'FAIL: timestamp {ts!r} does not match ISO 8601 UTC', file=sys.stderr)
    sys.exit(1)
PY
  assert_success
}
