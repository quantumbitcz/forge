#!/usr/bin/env bats

setup() {
  SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"
  TMP=$(mktemp -d)
}
teardown() { rm -rf "$TMP"; }

@test "persist writes cand-{N}.json to run dir" {
  payload='{"run_id":"r1","candidate_id":"cand-1","emphasis_axis":"simplicity","exploration_seed":1,"plan_hash":"h","plan_content":"x","validator_verdict":"GO","validator_score":80,"selection_score":80.0,"selected":false,"tokens":{"planner":100,"validator":50},"created_at":"2026-04-19T12:00:00Z"}'
  run python3 "$SPEC" persist-candidate --forge-dir "$TMP" --run-id r1 --candidate-json "$payload"
  [ "$status" -eq 0 ]
  [ -f "$TMP/plans/candidates/r1/cand-1.json" ]
  [ -f "$TMP/plans/candidates/index.json" ]
}

@test "persist updates index.json with run_id" {
  payload='{"run_id":"r1","candidate_id":"cand-1","emphasis_axis":"a","exploration_seed":1,"plan_hash":"h","plan_content":"x","validator_verdict":"GO","validator_score":80,"selection_score":80.0,"selected":false,"tokens":{"planner":100,"validator":50},"created_at":"2026-04-19T12:00:00Z"}'
  python3 "$SPEC" persist-candidate --forge-dir "$TMP" --run-id r1 --candidate-json "$payload"
  run grep -q '"r1"' "$TMP/plans/candidates/index.json"
  [ "$status" -eq 0 ]
}

@test "FIFO evicts oldest after 20 runs" {
  payload_tmpl='{"run_id":"RID","candidate_id":"cand-1","emphasis_axis":"a","exploration_seed":1,"plan_hash":"h","plan_content":"x","validator_verdict":"GO","validator_score":80,"selection_score":80.0,"selected":false,"tokens":{"planner":100,"validator":50},"created_at":"CT"}'
  for i in $(seq 1 22); do
    p=$(printf '%s' "$payload_tmpl" | sed "s/RID/run-$i/;s/CT/2026-04-19T12:00:${i}Z/")
    python3 "$SPEC" persist-candidate --forge-dir "$TMP" --run-id "run-$i" --candidate-json "$p"
  done
  [ ! -d "$TMP/plans/candidates/run-1" ]
  [ ! -d "$TMP/plans/candidates/run-2" ]
  [ -d "$TMP/plans/candidates/run-3" ]
  [ -d "$TMP/plans/candidates/run-22" ]
}
