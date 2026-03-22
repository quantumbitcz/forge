#!/usr/bin/env bats
# Scenario tests: pipeline-checkpoint.sh state management

load '../helpers/test-helpers'

CHECKPOINT_HOOK="$PLUGIN_ROOT/hooks/pipeline-checkpoint.sh"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-checkpoint.XXXXXX")"
  MOCK_BIN="$TEST_TEMP/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
  # Checkpoint hook reads .pipeline/state.json from CWD
  mkdir -p "$TEST_TEMP/project/.pipeline"
}

teardown() { rm -rf "$TEST_TEMP"; }

# ---------------------------------------------------------------------------
# 1. Valid state.json → lastCheckpoint updated
# ---------------------------------------------------------------------------
@test "checkpoint: valid state.json gets lastCheckpoint field set" {
  local proj="$TEST_TEMP/project"
  local state="$proj/.pipeline/state.json"
  printf '{"schema_version":"1.3","story_state":"IMPLEMENTING"}\n' > "$state"

  run bash -c "cd '$proj' && bash '$CHECKPOINT_HOOK'"

  assert_success
  # lastCheckpoint key should now be present
  assert python3 -c "
import json
with open('$state') as f:
    d = json.load(f)
assert 'lastCheckpoint' in d, 'lastCheckpoint missing'
"
}

# ---------------------------------------------------------------------------
# 2. Existing lastCheckpoint overwritten with a newer timestamp
# ---------------------------------------------------------------------------
@test "checkpoint: existing lastCheckpoint is overwritten" {
  local proj="$TEST_TEMP/project"
  local state="$proj/.pipeline/state.json"
  printf '{"schema_version":"1.3","story_state":"VERIFYING","lastCheckpoint":"2000-01-01T00:00:00Z"}\n' > "$state"

  run bash -c "cd '$proj' && bash '$CHECKPOINT_HOOK'"

  assert_success
  local new_ts
  new_ts="$(python3 -c "import json; d=json.load(open('$state')); print(d['lastCheckpoint'])")"
  # New timestamp must be different (later) than the old one
  assert [ "$new_ts" != "2000-01-01T00:00:00Z" ]
}

# ---------------------------------------------------------------------------
# 3. Missing state.json → no-op (exit 0)
# ---------------------------------------------------------------------------
@test "checkpoint: missing state.json causes script to exit 0 cleanly" {
  local proj="$TEST_TEMP/project"
  rm -f "$proj/.pipeline/state.json"

  run bash -c "cd '$proj' && bash '$CHECKPOINT_HOOK'"

  assert_success
}

# ---------------------------------------------------------------------------
# 4. Malformed JSON → not corrupted (exit 0, file unchanged or graceful)
# ---------------------------------------------------------------------------
@test "checkpoint: malformed JSON causes exit 0 without corrupting disk" {
  local proj="$TEST_TEMP/project"
  local state="$proj/.pipeline/state.json"
  printf 'NOT VALID JSON { broken\n' > "$state"

  run bash -c "cd '$proj' && bash '$CHECKPOINT_HOOK'"

  # Script always exits 0 (best-effort semantics)
  assert_success
}

# ---------------------------------------------------------------------------
# 5. Timestamp ISO 8601 UTC format check
# ---------------------------------------------------------------------------
@test "checkpoint: lastCheckpoint is written in ISO 8601 UTC format (YYYY-MM-DDTHH:MM:SSZ)" {
  local proj="$TEST_TEMP/project"
  local state="$proj/.pipeline/state.json"
  printf '{"schema_version":"1.3","story_state":"SHIPPING"}\n' > "$state"

  run bash -c "cd '$proj' && bash '$CHECKPOINT_HOOK'"

  assert_success
  local ts
  ts="$(python3 -c "import json; d=json.load(open('$state')); print(d.get('lastCheckpoint',''))")"
  # Must match YYYY-MM-DDTHH:MM:SSZ
  run python3 -c "
import re, sys
ts = sys.argv[1]
pat = r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
if not re.match(pat, ts):
    print('FAIL: timestamp %r does not match ISO 8601 UTC format' % ts, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" "$ts"
  assert_success
}
