#!/usr/bin/env bats
# Unit tests: forge-token-tracker.sh — token estimation, recording, and budget checking.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-token-tracker.sh"
STATE_WRITER="$PLUGIN_ROOT/shared/forge-state-write.sh"

@test "forge-token-tracker: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-token-tracker: estimate counts chars/4 from file" {
  local test_file="$TEST_TEMP/test.txt"
  # 400 chars = 100 tokens (roughly)
  python3 -c "print('x' * 400, end='')" > "$test_file"
  run bash "$SCRIPT" estimate "$test_file"
  assert_success
  assert_output "100"
}

@test "forge-token-tracker: estimate handles empty file" {
  local test_file="$TEST_TEMP/empty.txt"
  touch "$test_file"
  run bash "$SCRIPT" estimate "$test_file"
  assert_success
  assert_output "0"
}

@test "forge-token-tracker: record updates state.json tokens section" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  # Create initial state with tokens section
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":0,"budget_ceiling":2000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false}}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" record explore fg-200-planner 5000 2000 --forge-dir "$forge_dir"
  assert_success

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert d['tokens']['estimated_total'] == 7000, d['tokens']['estimated_total']
assert d['tokens']['by_stage']['explore']['input'] == 5000
assert d['tokens']['by_stage']['explore']['output'] == 2000
assert d['tokens']['by_agent']['fg-200-planner']['input'] == 5000
assert d['tokens']['by_agent']['fg-200-planner']['output'] == 2000
"
}

@test "forge-token-tracker: record accumulates across multiple calls" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":0,"budget_ceiling":2000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false}}' --forge-dir "$forge_dir"

  bash "$SCRIPT" record explore fg-200-planner 5000 2000 --forge-dir "$forge_dir"
  bash "$SCRIPT" record plan fg-200-planner 3000 1000 --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert d['tokens']['estimated_total'] == 11000
assert d['tokens']['by_agent']['fg-200-planner']['input'] == 8000
assert d['tokens']['by_agent']['fg-200-planner']['output'] == 3000
"
}

@test "forge-token-tracker: check exits 0 when within budget" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":100000,"budget_ceiling":2000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false}}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert_success
}

@test "forge-token-tracker: check exits 1 at 80% of budget (warning)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":1600000,"budget_ceiling":2000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false}}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert_failure
  [ "$status" -eq 1 ]
  assert_output --partial "WARNING"
}

@test "forge-token-tracker: check exits 2 when budget exceeded" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":2100000,"budget_ceiling":2000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false}}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "EXCEEDED"
}

@test "forge-token-tracker: check exits 0 when ceiling is 0 (no limit)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":9999999,"budget_ceiling":0,"by_stage":{},"by_agent":{},"budget_warning_issued":false}}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert_success
}

@test "forge-token-tracker: check handles missing tokens section gracefully" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" check --forge-dir "$forge_dir"
  assert_success
}

@test "forge-token-tracker: dispatch_count increments per agent" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":0,"budget_ceiling":2000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false}}' --forge-dir "$forge_dir"

  bash "$SCRIPT" record implementing fg-300-implementer 5000 2000 sonnet --forge-dir "$forge_dir"
  bash "$SCRIPT" record implementing fg-300-implementer 3000 1500 sonnet --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
agent = d['tokens']['by_agent']['fg-300-implementer']
assert agent.get('dispatch_count') == 2, f'expected 2, got {agent.get(\"dispatch_count\")}'
"
}

@test "forge-token-tracker: per-stage cost computed from agent costs" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":0,"budget_ceiling":2000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false},"cost":{"wall_time_seconds":0,"stages_completed":0,"estimated_cost_usd":0.0}}' --forge-dir "$forge_dir"

  bash "$SCRIPT" record implementing fg-300-implementer 10000 5000 sonnet --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
per_stage = d.get('cost', {}).get('per_stage', {})
assert isinstance(per_stage, dict), f'per_stage should be dict, got {type(per_stage)}'
assert d['cost']['estimated_cost_usd'] > 0, d['cost']['estimated_cost_usd']
"
}

@test "forge-token-tracker: budget_remaining_tokens computed" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":0,"budget_ceiling":1000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false},"cost":{"wall_time_seconds":0,"stages_completed":0,"estimated_cost_usd":0.0}}' --forge-dir "$forge_dir"

  bash "$SCRIPT" record implementing fg-300-implementer 50000 20000 sonnet --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
remaining = d['cost'].get('budget_remaining_tokens')
assert remaining is not None, 'budget_remaining_tokens missing'
assert remaining == 930000, f'expected 930000, got {remaining}'
"
}

@test "forge-token-tracker: model_costs config overrides default pricing" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$STATE_WRITER" write '{"version":"1.5.0","_seq":0,"tokens":{"estimated_total":0,"budget_ceiling":2000000,"by_stage":{},"by_agent":{},"budget_warning_issued":false},"cost":{"wall_time_seconds":0,"stages_completed":0,"estimated_cost_usd":0.0}}' --forge-dir "$forge_dir"

  bash "$SCRIPT" record implementing fg-300-implementer 1000000 500000 sonnet --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
# Default sonnet pricing: input 3.0/MTok, output 15.0/MTok
# 1M input * 3.0/1M + 500K output * 15.0/1M = 3.0 + 7.5 = 10.5
cost = d['cost']['estimated_cost_usd']
assert 10.0 < cost < 11.0, f'expected ~10.5, got {cost}'
"
}
