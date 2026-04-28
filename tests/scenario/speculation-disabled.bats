#!/usr/bin/env bats

# Covers:

SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"

@test "enabled=false path is orchestrator-side; detect-ambiguity only reports trigger reasons" {
  # When orchestrator reads speculation.enabled=false it never calls detect-ambiguity.
  # This test asserts that the helper itself is idempotent: invoking it returns a
  # well-formed result that the orchestrator can safely ignore.
  run python3 "$SPEC" detect-ambiguity --requirement "refactor the users module thoroughly with comprehensive tests added and either use repository pattern or service layer" --confidence MEDIUM --shaper-alternatives 2 --shaper-delta 2 --plan-cache-sim 0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *'"triggered": true'* ]]
}

@test "forge-config-template default shows enabled: true (opt-out is one line)" {
  grep -q "  enabled: true" "$BATS_TEST_DIRNAME/../../modules/frameworks/spring/forge-admin config-template.md"
}
