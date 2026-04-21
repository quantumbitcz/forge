#!/usr/bin/env bats

load '../lib/bats-support/load'
load '../lib/bats-assert/load'

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PYTHONPATH="$ROOT"
  TMPDIR="$(mktemp -d)"
  export _ORIG_CWD="$PWD"
  cd "$TMPDIR"
  mkdir -p ".forge/runs/r-soft/handoffs"
  cat > ".forge/state.json" <<EOF
{"run_id":"r-soft","story_state":"REVIEWING","autonomous":false,
 "requirement":"test soft handoff",
 "tokens":{"total":{"prompt":105000,"completion":0}},
 "handoff":{"chain":[],"soft_triggers_this_run":0,"hard_triggers_this_run":0,
            "milestone_triggers_this_run":0,"suppressed_by_rate_limit":0}}
EOF
}

teardown() {
  cd "$_ORIG_CWD"
  rm -rf "$TMPDIR"
}

@test "soft threshold (50%) writes a light handoff and emits alert" {
  run python3 -m hooks._py.handoff.cli write --level soft --variant light --reason context_soft_50pct
  [ "$status" -eq 0 ]
  files=$(ls .forge/runs/r-soft/handoffs/*soft*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$files" = "1" ]
  [ -f .forge/alerts.json ]
  grep -q '"type": "HANDOFF_WRITTEN"' .forge/alerts.json
  grep -q '"level": "soft"' .forge/alerts.json
}
