#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  # Expand $PLUGIN_ROOT into the heredoc at runtime — keeps the Python body
  # itself free of bash interpolation so `sys.argv[1]` isn't mangled.
  export _VALIDATOR_PY="$BATS_TEST_TMPDIR/run_validator.py"
  cat > "$_VALIDATOR_PY" <<PY
import sys, yaml
sys.path.insert(0, "$PLUGIN_ROOT/shared")
from config_validator import validate_cost_block
cfg = yaml.safe_load(open(sys.argv[1]).read())
for sev, msg in validate_cost_block(cfg):
    print(f"{sev}|{msg}")
PY
}

@test "preflight: warn_at > throttle_at -> CRITICAL" {
  local tmp="$BATS_TEST_TMPDIR/cfg.yaml"
  cat > "$tmp" <<'YAML'
cost:
  ceiling_usd: 25.00
  warn_at: 0.90
  throttle_at: 0.80
  abort_at: 1.00
  aware_routing: true
  tier_estimates_usd: {fast: 0.016, standard: 0.047, premium: 0.078}
  conservatism_multiplier: {fast: 1.0, standard: 1.0, premium: 1.0}
  skippable_under_cost_pressure: []
YAML
  run python3 "$_VALIDATOR_PY" "$tmp"
  assert_success
  assert_output -p "CRITICAL|cost thresholds must satisfy warn_at < throttle_at"
}

@test "preflight: skippable_under_cost_pressure contains SAFETY_CRITICAL -> CRITICAL" {
  local tmp="$BATS_TEST_TMPDIR/cfg.yaml"
  cat > "$tmp" <<'YAML'
cost:
  ceiling_usd: 25.00
  warn_at: 0.75
  throttle_at: 0.80
  abort_at: 1.00
  aware_routing: true
  tier_estimates_usd: {fast: 0.016, standard: 0.047, premium: 0.078}
  conservatism_multiplier: {fast: 1.0, standard: 1.0, premium: 1.0}
  skippable_under_cost_pressure: [fg-411-security-reviewer]
YAML
  run python3 "$_VALIDATOR_PY" "$tmp"
  assert_success
  assert_output -p "CRITICAL|cost.skippable_under_cost_pressure may not contain SAFETY_CRITICAL"
}

@test "preflight: conservatism_multiplier.premium = 0.5 -> CRITICAL" {
  local tmp="$BATS_TEST_TMPDIR/cfg.yaml"
  cat > "$tmp" <<'YAML'
cost:
  ceiling_usd: 25.00
  warn_at: 0.75
  throttle_at: 0.80
  abort_at: 1.00
  aware_routing: true
  tier_estimates_usd: {fast: 0.016, standard: 0.047, premium: 0.078}
  conservatism_multiplier: {fast: 1.0, standard: 1.0, premium: 0.5}
  skippable_under_cost_pressure: []
YAML
  run python3 "$_VALIDATOR_PY" "$tmp"
  assert_success
  assert_output -p "CRITICAL|cost.conservatism_multiplier.premium must be >= 1.0"
}

@test "preflight: aware_routing: true + model_routing.enabled: false -> CRITICAL" {
  local tmp="$BATS_TEST_TMPDIR/cfg.yaml"
  cat > "$tmp" <<'YAML'
model_routing: {enabled: false}
cost:
  ceiling_usd: 25.00
  warn_at: 0.75
  throttle_at: 0.80
  abort_at: 1.00
  aware_routing: true
  tier_estimates_usd: {fast: 0.016, standard: 0.047, premium: 0.078}
  conservatism_multiplier: {fast: 1.0, standard: 1.0, premium: 1.0}
  skippable_under_cost_pressure: []
YAML
  run python3 "$_VALIDATOR_PY" "$tmp"
  assert_success
  assert_output -p "CRITICAL|cost.aware_routing: true requires model_routing.enabled: true"
}
