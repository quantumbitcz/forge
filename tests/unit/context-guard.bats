#!/usr/bin/env bats
# Unit tests: context-guard.sh — context degradation protection.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/context-guard.sh"
STATE_WRITER="$PLUGIN_ROOT/shared/forge-state-write.sh"

# Helper: create state.json with context guard enabled
_setup_guard_state() {
  local forge_dir="$1"
  local existing_triggers="${2:-0}"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write "$(python3 -c "
import json
state = {
  'version': '1.5.0', '_seq': 0,
  'story_state': 'IMPLEMENTING',
  'tokens': {'estimated_total': 50000, 'budget_ceiling': 2000000, 'by_stage': {}, 'by_agent': {}},
  'context': {
    'peak_tokens': 0,
    'condensation_triggers': $existing_triggers,
    'per_stage_peak': {},
    'last_estimated_tokens': 0,
    'guard_checks': 0
  }
}
print(json.dumps(state))
")" --forge-dir "$forge_dir"
}

@test "context-guard: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "context-guard: requires a command" {
  run bash "$SCRIPT"
  assert_failure
}

@test "context-guard: check returns OK below threshold" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_guard_state "$forge_dir"
  run bash "$SCRIPT" check 20000 --forge-dir "$forge_dir"
  assert_success
  [[ "$output" == *"OK:"* ]]
}

@test "context-guard: check returns CONDENSED (exit 1) above condensation threshold" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_guard_state "$forge_dir"
  run bash "$SCRIPT" check 35000 --forge-dir "$forge_dir"
  assert [ "$status" -eq 1 ]
  [[ "$output" == *"CONDENSED:"* ]]
}

@test "context-guard: check returns CRITICAL (exit 2) after max_condensation_triggers" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_guard_state "$forge_dir" 4  # 4 existing triggers, this will be the 5th
  run bash "$SCRIPT" check 35000 --forge-dir "$forge_dir"
  assert [ "$status" -eq 2 ]
  [[ "$output" == *"CRITICAL:"* ]]
}

@test "context-guard: disabled via config returns DISABLED" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_guard_state "$forge_dir"
  # Write a minimal forge-config.md with context_guard disabled
  # context-guard reads from FORGE_CONFIG_DIR env var
  mkdir -p "$TEST_TEMP/config"
  cat > "$TEST_TEMP/config/forge-config.md" <<'CFGEOF'
---
context_guard:
  enabled: false
---
CFGEOF
  FORGE_CONFIG_DIR="$TEST_TEMP/config" run bash "$SCRIPT" check 35000 --forge-dir "$forge_dir"
  # Should exit 10 (disabled)
  assert [ "$status" -eq 10 ]
}

@test "context-guard: peak_tokens updated on each check" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_guard_state "$forge_dir"
  bash "$SCRIPT" check 15000 --forge-dir "$forge_dir"
  bash "$SCRIPT" check 25000 --forge-dir "$forge_dir"
  bash "$SCRIPT" check 10000 --forge-dir "$forge_dir"

  python3 - "$forge_dir/state.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
assert d['context']['peak_tokens'] == 25000, d['context']['peak_tokens']
PYEOF
}

@test "context-guard: guard_checks counter increments" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_guard_state "$forge_dir"
  bash "$SCRIPT" check 10000 --forge-dir "$forge_dir"
  bash "$SCRIPT" check 12000 --forge-dir "$forge_dir"
  bash "$SCRIPT" check 8000 --forge-dir "$forge_dir"

  python3 - "$forge_dir/state.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
assert d['context']['guard_checks'] == 3, d['context']['guard_checks']
PYEOF
}

@test "context-guard: metrics command outputs all fields" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_guard_state "$forge_dir"
  bash "$SCRIPT" check 15000 --forge-dir "$forge_dir"

  run bash "$SCRIPT" metrics --forge-dir "$forge_dir"
  assert_success
  [[ "$output" == *"peak_tokens"* ]]
  [[ "$output" == *"condensation_triggers"* ]]
  [[ "$output" == *"guard_checks"* ]]
}

@test "context-guard: condensation_triggers increments correctly across multiple checks" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_guard_state "$forge_dir" 0

  # First trigger (above 30K threshold) — exits 1 (CONDENSED)
  bash "$SCRIPT" check 35000 --forge-dir "$forge_dir" || true

  # Second trigger — exits 1 (CONDENSED)
  bash "$SCRIPT" check 32000 --forge-dir "$forge_dir" || true

  # Below threshold -- should not increment
  bash "$SCRIPT" check 20000 --forge-dir "$forge_dir"

  python3 - "$forge_dir/state.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
assert d['context']['condensation_triggers'] == 2, d['context']['condensation_triggers']
assert d['context']['guard_checks'] == 3, d['context']['guard_checks']
PYEOF
}

@test "context-guard: per_stage_peak tracks per stage" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  # State at IMPLEMENTING
  bash "$STATE_WRITER" write "$(python3 -c "
import json
state = {
  'version': '1.5.0', '_seq': 0,
  'story_state': 'IMPLEMENTING',
  'tokens': {'estimated_total': 50000, 'budget_ceiling': 2000000, 'by_stage': {}, 'by_agent': {}},
  'context': {'peak_tokens': 0, 'condensation_triggers': 0, 'per_stage_peak': {}, 'last_estimated_tokens': 0, 'guard_checks': 0}
}
print(json.dumps(state))
")" --forge-dir "$forge_dir"

  bash "$SCRIPT" check 20000 --forge-dir "$forge_dir"

  # Change state to REVIEWING
  local state
  state=$(bash "$STATE_WRITER" read --forge-dir "$forge_dir")
  state=$(echo "$state" | python3 -c "
import json, sys
s = json.load(sys.stdin)
s['story_state'] = 'REVIEWING'
json.dump(s, sys.stdout)
")
  bash "$STATE_WRITER" write "$state" --forge-dir "$forge_dir"

  bash "$SCRIPT" check 15000 --forge-dir "$forge_dir"

  python3 - "$forge_dir/state.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
peaks = d['context']['per_stage_peak']
assert peaks.get('implementing') == 20000, peaks
assert peaks.get('reviewing') == 15000, peaks
PYEOF
}

@test "context-guard: critical_threshold triggers condensation before critical" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_guard_state "$forge_dir" 0

  # Above critical threshold (50K default) -- should still CONDENSE (triggers < max)
  run bash "$SCRIPT" check 55000 --forge-dir "$forge_dir"
  assert [ "$status" -eq 1 ]
  [[ "$output" == *"CONDENSED:"* ]]
}
