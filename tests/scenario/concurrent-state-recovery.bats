#!/usr/bin/env bats
# Scenario test: concurrent state recovery from WAL

# Covers:

load '../helpers/test-helpers'

STATE_WRITER="$PLUGIN_ROOT/shared/forge-state-write.sh"

@test "concurrent-recovery: 5 parallel reads with missing state.json all succeed" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  echo '--- SEQ:1 TS:2026-04-14T10:00:00Z ---' > "$forge_dir/state.wal"
  echo '{"version":"1.5.0","_seq":1,"story_state":"REVIEWING"}' >> "$forge_dir/state.wal"

  local pids=()
  for i in 1 2 3 4 5; do
    bash "$STATE_WRITER" read --forge-dir "$forge_dir" > "$TEST_TEMP/output_${i}.json" 2>/dev/null &
    pids+=($!)
  done

  local failures=0
  for pid in "${pids[@]}"; do
    wait "$pid" || failures=$((failures + 1))
  done
  [[ "$failures" -eq 0 ]] || fail "$failures of 5 parallel reads failed"

  for i in 1 2 3 4 5; do
    python3 - "$TEST_TEMP/output_${i}.json" <<'PY' || fail "output_${i}.json has invalid content"
import json
import sys
from pathlib import Path

with Path(sys.argv[1]).open() as f:
    d = json.load(f)
assert d['story_state'] == 'REVIEWING'
PY
  done

  assert [ -f "$forge_dir/state.json" ]
  assert [ -f "$forge_dir/state.wal" ]
}
