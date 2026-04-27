#!/usr/bin/env bats
load '../helpers/test-helpers'

skip_if_no_otel() {
  python3 -c "import opentelemetry" 2>/dev/null || skip "opentelemetry not installed"
}

@test "replay emits forge.run.budget_total_usd on agent spans" {
  skip_if_no_otel
  run python3 -c "
import sys, pathlib
sys.path.insert(0, '$PLUGIN_ROOT')
from hooks._py.otel import replay
# Use the console exporter to capture output.
cfg = {'enabled': True, 'exporter': 'console', 'endpoint': '', 'sample_rate': 1.0,
       'service_name': 'forge-test', 'openinference_compat': False,
       'include_tool_spans': False, 'batch_size': 32, 'flush_interval_seconds': 2}
replay(events_path='$PLUGIN_ROOT/tests/fixtures/events-cost-attrs.jsonl', config=cfg)
" 2>&1
  assert_success
  assert_output -p 'forge.run.budget_total_usd'
  assert_output -p 'forge.run.budget_remaining_usd'
  assert_output -p 'forge.agent.tier_estimate_usd'
  assert_output -p 'forge.agent.tier_original'
  assert_output -p 'forge.agent.tier_used'
  assert_output -p 'forge.cost.throttle_reason'
}

@test "replay preserves tier_original != tier_used on downgrade events" {
  skip_if_no_otel
  # Build a downgrade event and assert both tier attributes survive replay.
  local tmp="$BATS_TEST_TMPDIR/events-downgrade.jsonl"
  cat > "$tmp" <<'EOF'
{"type":"dispatch_start","gen_ai.agent.name":"fg-200-planner","forge.agent.tier_original":"premium","forge.agent.tier_used":"standard","forge.cost.throttle_reason":"dynamic_downgrade"}
EOF
  run python3 -c "
import sys
sys.path.insert(0, '$PLUGIN_ROOT')
from hooks._py.otel import replay
cfg = {'enabled': True, 'exporter': 'console', 'endpoint': '', 'sample_rate': 1.0,
       'service_name': 'forge-test', 'openinference_compat': False,
       'include_tool_spans': False, 'batch_size': 32, 'flush_interval_seconds': 2}
replay(events_path='$tmp', config=cfg)
" 2>&1
  assert_success
  assert_output -p 'tier_original": "premium"'
  assert_output -p 'tier_used": "standard"'
  assert_output -p 'throttle_reason": "dynamic_downgrade"'
}
