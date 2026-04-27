#!/usr/bin/env bats

# Covers:

setup() {
  SIM="$BATS_TEST_DIRNAME/../../shared/forge-sim.sh"
  SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"
  TMP=$(mktemp -d)
  export FORGE_DIR="$TMP/.forge"
  mkdir -p "$FORGE_DIR"
}
teardown() { rm -rf "$TMP"; }

@test "happy path: MEDIUM + shaper signal -> 3 candidates -> top-1 wins decisively" {
  run python3 "$SPEC" pick-winner --auto-pick-threshold-delta 5 --mode autonomous \
    --candidate 'cand-1:GO:90:4000' --candidate 'cand-2:GO:82:4200' --candidate 'cand-3:GO:78:3900'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"winner_id": "cand-1"'* ]]
  [[ "$output" == *'"needs_confirmation": false'* ]]
  [[ "$output" == *'"reasoning": "decisive_top_score"'* ]]
}

@test "happy path: losers persisted" {
  payload='{"run_id":"rh","candidate_id":"cand-2","emphasis_axis":"robustness","exploration_seed":9,"plan_hash":"h","plan_content":"p","validator_verdict":"GO","validator_score":82,"selection_score":82.0,"selected":false,"tokens":{"planner":4200,"validator":2000},"created_at":"2026-04-19T14:30:00Z"}'
  run python3 "$SPEC" persist-candidate --forge-dir "$FORGE_DIR" --run-id rh --candidate-json "$payload"
  [ "$status" -eq 0 ]
  [ -f "$FORGE_DIR/plans/candidates/rh/cand-2.json" ]
}
