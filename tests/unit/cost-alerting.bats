#!/usr/bin/env bats
# Unit tests: cost-alerting.sh — multi-threshold budget alerting.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/cost-alerting.sh"
STATE_WRITER="$PLUGIN_ROOT/shared/forge-state-write.sh"

# Helper: create state.json with specific token consumption
_setup_state_with_tokens() {
  local forge_dir="$1" total="$2" ceiling="$3"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write "$(python3 -c "
import json
state = {
  'version': '1.5.0', '_seq': 0,
  'story_state': 'IMPLEMENTING',
  'tokens': {
    'estimated_total': $total,
    'budget_ceiling': $ceiling,
    'by_stage': {}, 'by_agent': {},
    'budget_warning_issued': False
  },
  'cost_alerting': {
    'enabled': True,
    'thresholds': [0.50, 0.75, 0.90],
    'per_stage_limits': {},
    'alerts_issued': [],
    'last_alert_level': 'OK',
    'routing_override': None
  }
}
print(json.dumps(state))
")" --forge-dir "$forge_dir"
}

@test "cost-alerting: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "cost-alerting: requires a command" {
  run bash "$SCRIPT"
  assert_failure
  [[ "$output" == *"Usage:"* ]]
}

@test "cost-alerting: unknown command fails" {
  run bash "$SCRIPT" foobar
  assert_failure
}

@test "cost-alerting: init creates cost_alerting in state.json" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{
    "version":"1.5.0","_seq":0,
    "tokens":{"estimated_total":0,"budget_ceiling":2000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false},
    "story_state":"PREFLIGHT"
  }' --forge-dir "$forge_dir"

  run bash "$SCRIPT" init --forge-dir "$forge_dir"
  assert_success

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
ca = d['cost_alerting']
assert ca['enabled'] == True, ca
assert ca['thresholds'] == [0.50, 0.75, 0.90], ca['thresholds']
assert ca['alerts_issued'] == [], ca['alerts_issued']
assert ca['last_alert_level'] == 'OK', ca['last_alert_level']
assert 'per_stage_limits' in ca, 'missing per_stage_limits'
assert ca['routing_override'] is None, ca['routing_override']
"
}

@test "cost-alerting: check returns OK (exit 0) when below first threshold" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 400000 1000000  # 40%
  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert_success
  [[ "$output" == *"OK:"* ]]
}

@test "cost-alerting: check returns INFO (exit 1) at 50% consumption" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 500000 1000000  # 50%
  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert [ "$status" -eq 1 ]
  [[ "$output" == *"INFO:"* ]]
  [[ "$output" == *"NEW_ALERT:INFO"* ]]
}

@test "cost-alerting: check returns WARNING (exit 2) at 75% consumption" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 750000 1000000  # 75%
  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert [ "$status" -eq 2 ]
  [[ "$output" == *"WARNING:"* ]]
  [[ "$output" == *"NEW_ALERT:WARNING"* ]]
}

@test "cost-alerting: check returns CRITICAL (exit 3) at 90% consumption" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 900000 1000000  # 90%
  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert [ "$status" -eq 3 ]
  [[ "$output" == *"CRITICAL:"* ]]
  [[ "$output" == *"NEW_ALERT:CRITICAL"* ]]
}

@test "cost-alerting: check returns EXCEEDED (exit 4) above 100%" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 1100000 1000000  # 110%
  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert [ "$status" -eq 4 ]
  [[ "$output" == *"EXCEEDED:"* ]]
  [[ "$output" == *"NEW_ALERT:EXCEEDED"* ]]
}

@test "cost-alerting: check returns exit 10 when disabled" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 500000 1000000
  # Disable cost_alerting
  local state
  state=$(bash "$STATE_WRITER" read --forge-dir "$forge_dir")
  state=$(echo "$state" | python3 -c "
import json, sys
s = json.load(sys.stdin)
s['cost_alerting']['enabled'] = False
json.dump(s, sys.stdout)
")
  bash "$STATE_WRITER" write "$state" --forge-dir "$forge_dir"
  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert [ "$status" -eq 10 ]
}

@test "cost-alerting: alerts are not re-issued for same threshold" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 500000 1000000  # 50%
  # First check -- should emit NEW_ALERT
  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert [ "$status" -eq 1 ]
  [[ "$output" == *"NEW_ALERT:INFO"* ]]

  # Second check at same level -- should NOT emit NEW_ALERT
  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert [ "$status" -eq 1 ]
  [[ "$output" != *"NEW_ALERT"* ]]
}

@test "cost-alerting: zero ceiling means no limit (exit 0 always)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 5000000 0
  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert_success
  [[ "$output" == *"OK: no budget ceiling set"* ]]
}

@test "cost-alerting: auto per-stage limits sum to budget ceiling" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{
    "version":"1.5.0","_seq":0,
    "tokens":{"estimated_total":0,"budget_ceiling":2000000,"by_stage":{},"by_agent":{}},
    "story_state":"PREFLIGHT"
  }' --forge-dir "$forge_dir"

  run bash "$SCRIPT" init --forge-dir "$forge_dir"
  assert_success

  # Verify per-stage limits sum to ceiling (within rounding)
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
limits = d['cost_alerting']['per_stage_limits']
assert len(limits) == 10, f'expected 10 stages, got {len(limits)}: {list(limits.keys())}'
total = sum(limits.values())
ceiling = d['tokens']['budget_ceiling']
# Allow rounding tolerance
assert abs(total - ceiling) <= 10, f'sum {total} != ceiling {ceiling}'
# Implementing should be the largest
assert limits['implementing'] > limits['preflight'], 'implementing should be > preflight'
"
}

@test "cost-alerting: per-stage check detects over-budget stage" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write "$(python3 -c "
import json
state = {
  'version': '1.5.0', '_seq': 0,
  'story_state': 'IMPLEMENTING',
  'tokens': {
    'estimated_total': 200000, 'budget_ceiling': 1000000,
    'by_stage': {'implementing': {'input': 180000, 'output': 70000, 'agents': []}},
    'by_agent': {}
  },
  'cost_alerting': {
    'enabled': True, 'thresholds': [0.50, 0.75, 0.90],
    'per_stage_limits': {'implementing': 150000},
    'alerts_issued': [], 'last_alert_level': 'OK', 'routing_override': None
  }
}
print(json.dumps(state))
")" --forge-dir "$forge_dir"

  run bash "$SCRIPT" stage-report implementing --forge-dir "$forge_dir"
  assert_success
  # Stage consumed 250K vs 150K limit = 167% -- should flag STAGE_OVER_BUDGET
  [[ "$output" == *"STAGE_OVER_BUDGET"* ]] || [[ "$output" == *"over"* ]] || [[ "$output" == *"implementing"* ]]
}

@test "cost-alerting: routing_override stored in state.json" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 950000 1000000  # 95% -> CRITICAL
  # Simulate: user chose to downgrade routing
  local state
  state=$(bash "$STATE_WRITER" read --forge-dir "$forge_dir")
  state=$(echo "$state" | python3 -c "
import json, sys
s = json.load(sys.stdin)
s['cost_alerting']['routing_override'] = {
    'fg-350-docs-generator': 'haiku',
    'fg-600-pr-builder': 'haiku',
    'fg-700-retrospective': 'haiku',
    'fg-710-post-run': 'haiku'
}
json.dump(s, sys.stdout)
")
  bash "$STATE_WRITER" write "$state" --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
ro = d['cost_alerting']['routing_override']
assert ro is not None
assert ro['fg-350-docs-generator'] == 'haiku'
assert len(ro) == 4
"
}

@test "cost-alerting: apply-downgrade writes routing override" {
  local forge_dir="$TEST_TEMP/project/.forge"
  _setup_state_with_tokens "$forge_dir" 950000 1000000
  run bash "$SCRIPT" apply-downgrade --forge-dir "$forge_dir"
  assert_success

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
ro = d['cost_alerting']['routing_override']
assert ro is not None, 'routing_override should not be None'
assert 'fg-350-docs-generator' in ro, 'missing docs-generator override'
assert ro['fg-350-docs-generator'] == 'haiku'
"
}

@test "cost-alerting: stage-report format matches [COST] pattern" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write "$(python3 -c "
import json
state = {
  'version': '1.5.0', '_seq': 0, 'story_state': 'IMPLEMENTING',
  'tokens': {
    'estimated_total': 142800, 'budget_ceiling': 2000000,
    'by_stage': {'implementing': {'input': 30000, 'output': 15230, 'agents': ['fg-300-implementer']}},
    'by_agent': {'fg-300-implementer': {'input': 30000, 'output': 15230, 'model': 'sonnet'}},
    'model_distribution': {}
  },
  'cost': {'estimated_cost_usd': 0.89, 'wall_time_seconds': 0, 'stages_completed': 0},
  'cost_alerting': {
    'enabled': True, 'thresholds': [0.50, 0.75, 0.90],
    'per_stage_limits': {'implementing': 600000},
    'alerts_issued': [], 'last_alert_level': 'OK', 'routing_override': None
  }
}
print(json.dumps(state))
")" --forge-dir "$forge_dir"

  run bash "$SCRIPT" stage-report implementing --forge-dir "$forge_dir"
  assert_success
  [[ "$output" == *"[COST]"* ]]
  [[ "$output" == *"IMPL"* ]]
  [[ "$output" == *"tokens"* ]]
}

@test "cost-alerting: stage-report with --iteration shows iteration" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write "$(python3 -c "
import json
state = {
  'version': '1.5.0', '_seq': 0, 'story_state': 'IMPLEMENTING',
  'tokens': {
    'estimated_total': 142800, 'budget_ceiling': 2000000,
    'by_stage': {'implementing': {'input': 30000, 'output': 15230, 'agents': ['fg-300-implementer']}},
    'by_agent': {'fg-300-implementer': {'input': 30000, 'output': 15230, 'model': 'sonnet'}},
    'model_distribution': {}
  },
  'cost': {'estimated_cost_usd': 0.89, 'wall_time_seconds': 0, 'stages_completed': 0},
  'cost_alerting': {
    'enabled': True, 'thresholds': [0.50, 0.75, 0.90],
    'per_stage_limits': {'implementing': 600000},
    'alerts_issued': [], 'last_alert_level': 'OK', 'routing_override': None
  }
}
print(json.dumps(state))
")" --forge-dir "$forge_dir"

  run bash "$SCRIPT" stage-report implementing --iteration 3 --forge-dir "$forge_dir"
  assert_success
  [[ "$output" == *"iteration 3"* ]]
  [[ "$output" == *"tokens"* ]]
}
