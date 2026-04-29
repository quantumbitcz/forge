#!/usr/bin/env bats
# Scenario: implementer soft throttle at 80% / 90% budget consumption.
# Mocks: state fixture with pre-set cost block; implementer called via
# tests/helpers/implementer-harness.bash (read-only dispatch simulator).

load '../helpers/test-helpers'
load '../helpers/implementer-harness'

setup() {
  export FORGE_DIR="$BATS_TEST_TMPDIR/.forge"
  mkdir -p "$FORGE_DIR"
  cp "$PLUGIN_ROOT/tests/fixtures/state-v2-cost.json" "$FORGE_DIR/state.json"
}

@test "implementer at 85% consumed: emits COST-THROTTLE-IMPL INFO, skips refactor #2, dispatches judge" {
  seed_state_cost_pct 0.85
  run implementer_harness run-task task-001
  assert_success
  assert_line -p "COST-THROTTLE-IMPL"
  assert_line -p "severity: INFO"
  refute_line -p "refactor pass #2 executed"
  assert_line -p "fg-301-implementer-judge dispatched"
}

@test "implementer at 95% consumed: emits COST-THROTTLE-IMPL WARNING, skips refactor, skips judge" {
  seed_state_cost_pct 0.95
  run implementer_harness run-task task-001
  assert_success
  assert_line -p "COST-THROTTLE-IMPL"
  assert_line -p "severity: WARNING"
  refute_line -p "refactor pass #2 executed"
  refute_line -p "fg-301-implementer-judge dispatched"
  assert_line -p "REFLECT_SKIPPED_COST"
  refute_line -p "REFLECT_EXHAUSTED"
}

@test "implementer at 99% consumed: RED/GREEN still run (correctness gates immune)" {
  seed_state_cost_pct 0.99
  run implementer_harness run-task task-001
  assert_success
  assert_line -p "RED phase executed"
  assert_line -p "GREEN phase executed"
}

@test "implementer at 95%: state.cost.throttle_events appended with severity WARNING" {
  seed_state_cost_pct 0.95
  implementer_harness run-task task-001
  run python3 -c "
import json, os
from pathlib import Path
st = json.load(open(Path(os.environ['FORGE_DIR']) / 'state.json'))
events = st['cost']['throttle_events']
assert len(events) >= 1, events
assert events[-1]['severity'] == 'WARNING', events[-1]
assert events[-1]['action'] == 'skip_refactor_and_judge', events[-1]
print('ok')
"
  assert_success
}
