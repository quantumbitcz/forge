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
