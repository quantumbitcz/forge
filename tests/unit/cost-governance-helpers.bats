#!/usr/bin/env bats
load '../helpers/test-helpers'

PY="python3 -c"
MODULE="$PLUGIN_ROOT/shared/cost_governance.py"

@test "cost_governance: module imports cleanly" {
  run python3 -c "import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared'); import cost_governance"
  assert_success
}

@test "compute_budget_block: renders Spent/Remaining/Tier lines" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import compute_budget_block
out = compute_budget_block(ceiling_usd=25.0, spent_usd=3.42, tier='standard', tier_estimate=0.047)
assert 'Spent: \$3.42 of \$25.00' in out, out
assert 'Remaining: \$21.58' in out, out
assert 'Your tier: standard' in out, out
assert 'est \$0.047 per iteration' in out, out
print('ok')
"
  assert_success
}

@test "compute_budget_block: ceiling=0 renders 'unlimited'" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import compute_budget_block
out = compute_budget_block(ceiling_usd=0.0, spent_usd=3.42, tier='standard', tier_estimate=0.047)
assert 'unlimited' in out.lower(), out
print('ok')
"
  assert_success
}

@test "project_spend: adds tier_estimate to spent" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import project_spend
assert abs(project_spend(24.50, 0.047) - 24.547) < 1e-6
print('ok')
"
  assert_success
}

@test "is_safety_critical: returns True for fg-411-security-reviewer" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import is_safety_critical
assert is_safety_critical('fg-411-security-reviewer') is True
print('ok')
"
  assert_success
}

@test "is_safety_critical: returns False for fg-410-code-reviewer" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import is_safety_critical
assert is_safety_critical('fg-410-code-reviewer') is False
print('ok')
"
  assert_success
}

@test "SAFETY_CRITICAL set contains exactly 10 entries (authoritative list)" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared')
from cost_governance import SAFETY_CRITICAL
assert len(SAFETY_CRITICAL) == 10, len(SAFETY_CRITICAL)
expected = {
    'fg-210-validator','fg-250-contract-validator','fg-411-security-reviewer',
    'fg-412-architecture-reviewer','fg-414-license-reviewer',
    'fg-419-infra-deploy-reviewer','fg-505-build-verifier','fg-500-test-gate',
    'fg-506-migration-verifier','fg-590-pre-ship-verifier'
}
assert SAFETY_CRITICAL == expected, SAFETY_CRITICAL ^ expected
print('ok')
"
  assert_success
}
