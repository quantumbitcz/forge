#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "shared/findings-store.md exists" {
  [ -f "$PROJECT_ROOT/shared/findings-store.md" ]
}

@test "findings-store.md declares path convention .forge/runs/<run_id>/findings/" {
  run grep -F ".forge/runs/<run_id>/findings/" "$PROJECT_ROOT/shared/findings-store.md"
  [ "$status" -eq 0 ]
}

@test "findings-store.md declares append-only semantics" {
  run grep -iF "append-only" "$PROJECT_ROOT/shared/findings-store.md"
  [ "$status" -eq 0 ]
}

@test "findings-store.md documents annotation inheritance rule verbatim phrase" {
  run grep -F "inherits \`severity\`, \`category\`, \`file\`, \`line\`, \`confidence\`, and \`message\` **verbatim**" "$PROJECT_ROOT/shared/findings-store.md"
  [ "$status" -eq 0 ]
}

@test "findings-store.md documents duplicate emission tiebreaker" {
  run grep -iF "tiebreaker" "$PROJECT_ROOT/shared/findings-store.md"
  [ "$status" -eq 0 ]
}

@test "stage-contract.md describes Agent Teams pattern for Stage 6" {
  F="$PROJECT_ROOT/shared/stage-contract.md"
  run grep -iF 'Agent Teams' "$F"
  [ "$status" -eq 0 ]
}

@test "stage-contract.md describes judge veto in Stage 2 and Stage 4" {
  F="$PROJECT_ROOT/shared/stage-contract.md"
  run grep -iF 'binding veto' "$F"
  [ "$status" -eq 0 ]
}

@test "agent-communication.md does not contain 'dedup hints' or 'previous batch findings'" {
  F="$PROJECT_ROOT/shared/agent-communication.md"
  run grep -iF 'dedup hints' "$F"
  [ "$status" -ne 0 ]
  run grep -iF 'previous batch findings' "$F"
  [ "$status" -ne 0 ]
}

@test "agent-communication.md references Findings Store Protocol" {
  F="$PROJECT_ROOT/shared/agent-communication.md"
  run grep -F 'Findings Store Protocol' "$F"
  [ "$status" -eq 0 ]
}
