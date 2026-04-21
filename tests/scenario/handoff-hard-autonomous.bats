#!/usr/bin/env bats

load '../lib/bats-support/load'
load '../lib/bats-assert/load'

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export PYTHONPATH="$ROOT"
  TMPDIR="$(mktemp -d)"
  export _ORIG_CWD="$PWD"
  cd "$TMPDIR"
  mkdir -p ".forge/runs/r-hard/handoffs"
  cat > ".forge/state.json" <<EOF
{"run_id":"r-hard","story_state":"REVIEWING","autonomous":true,
 "requirement":"autonomous hard threshold",
 "tokens":{"total":{"prompt":150000,"completion":0}},
 "handoff":{"chain":[],"soft_triggers_this_run":0,"hard_triggers_this_run":0,
            "milestone_triggers_this_run":0,"suppressed_by_rate_limit":0}}
EOF
}

teardown() {
  cd "$_ORIG_CWD"
  rm -rf "$TMPDIR"
}

@test "autonomous hard threshold writes full handoff and does NOT raise CONTEXT_CRITICAL" {
  run python3 -m hooks._py.handoff.cli write --level hard --variant full --reason context_hard_70pct
  [ "$status" -eq 0 ]
  files=$(ls .forge/runs/r-hard/handoffs/*hard*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$files" = "1" ]
  # Alert written
  grep -q "HANDOFF_WRITTEN" .forge/alerts.json
  # No CONTEXT_CRITICAL escalation in autonomous mode
  ! grep -q "CONTEXT_CRITICAL" .forge/alerts.json
}
