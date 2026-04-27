#!/usr/bin/env bats
load '../helpers/test-helpers'

TIERS='{"fast":0.016,"standard":0.047,"premium":0.078}'
BUFFER='{"fast":1.0,"standard":1.0,"premium":1.0}'

_call() {
  local agent="$1" tier="$2" remaining="$3" pinned="${4:-[]}" aware="${5:-True}"
  python3 -c "
import json, sys
sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
t, r = downgrade_tier(
    agent='$agent', resolved_tier='$tier', remaining_usd=$remaining,
    tier_estimates=json.loads('$TIERS'),
    conservatism_multiplier=json.loads('$BUFFER'),
    pinned_agents=json.loads('$pinned'),
    aware_routing=$aware,
)
print(f'{t}|{r}')
"
}

@test "downgrade: premium with ample remaining — no change (AC-607 negative)" {
  run _call "fg-200-planner" "premium" "10.00"
  assert_success
  assert_output "premium|no_downgrade"
}

@test "downgrade: premium with remaining < 5*0.078 — step down to standard (AC-607)" {
  run _call "fg-200-planner" "premium" "0.20"
  assert_success
  assert_output "standard|downgrade_from_premium"
}

@test "downgrade: standard with remaining < 5*0.047 — step down to fast" {
  run _call "fg-300-implementer" "standard" "0.10"
  assert_success
  assert_output "fast|downgrade_from_standard"
}

@test "downgrade: fast non-safety-critical with remaining < 5*0.016 — escalate_required" {
  run _call "fg-410-code-reviewer" "fast" "0.02"
  assert_success
  assert_output "fast|escalate_required"
}

@test "downgrade: fast + fg-411-security-reviewer — safety_pinned (AC-608)" {
  run _call "fg-411-security-reviewer" "fast" "0.02"
  assert_success
  assert_output "fast|safety_pinned"
}

@test "downgrade: premium + pinned agent stays premium (AC-609)" {
  run _call "fg-200-planner" "premium" "0.20" '["fg-200-planner"]'
  assert_success
  assert_output "premium|agent_pinned"
}

@test "downgrade: aware_routing disabled — no-op regardless of remaining" {
  run _call "fg-412-architecture-reviewer" "premium" "0.01" "[]" "False"
  assert_success
  assert_output "premium|aware_routing_disabled"
}

@test "downgrade: conservatism_multiplier=3.0 on premium trips earlier" {
  # 5 * 0.078 * 3.0 = 1.17 — remaining 1.00 < 1.17 triggers downgrade.
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import downgrade_tier
t, r = downgrade_tier(
    agent='fg-200-planner', resolved_tier='premium', remaining_usd=1.00,
    tier_estimates={'fast':0.016,'standard':0.047,'premium':0.078},
    conservatism_multiplier={'fast':1.0,'standard':1.0,'premium':3.0},
    pinned_agents=[], aware_routing=True,
)
print(f'{t}|{r}')
"
  assert_success
  assert_output "standard|downgrade_from_premium"
}
