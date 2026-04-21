#!/usr/bin/env bats

load '../lib/bats-support/load'
load '../lib/bats-assert/load'

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PYTHONPATH="$ROOT"
  TMPDIR="$(mktemp -d)"
  export _ORIG_CWD="$PWD"
  export FORGE_HANDOFF_CHAIN_LIMIT=3
  cd "$TMPDIR"
  mkdir -p ".forge/runs/r-chain/handoffs"
  cat > ".forge/state.json" <<EOF
{"run_id":"r-chain","story_state":"X","requirement":"chain rotation test",
 "handoff":{"chain":[],"soft_triggers_this_run":0,"hard_triggers_this_run":0,
            "milestone_triggers_this_run":0,"suppressed_by_rate_limit":0}}
EOF
}

teardown() {
  cd "$_ORIG_CWD"
  unset FORGE_HANDOFF_CHAIN_LIMIT
  rm -rf "$TMPDIR"
}

@test "chain_limit=3 rotates oldest handoffs to archive" {
  for i in 1 2 3 4 5; do
    run python3 -m hooks._py.handoff.cli write --level manual --reason "test$i"
    [ "$status" -eq 0 ]
    sleep 1
  done
  active=$(ls .forge/runs/r-chain/handoffs/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$active" = "3" ]
  archived=$(ls .forge/runs/r-chain/handoffs/archive/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$archived" = "2" ]
}
