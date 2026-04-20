#!/usr/bin/env bats

@test "spec documents .forge/plans/candidates/ layout" {
  grep -q ".forge/plans/candidates/{run_id}/cand-{N}.json" \
    "$BATS_TEST_DIRNAME/../../shared/speculation.md"
}

@test "spec documents index.json + FIFO eviction" {
  grep -q "index.json" "$BATS_TEST_DIRNAME/../../shared/speculation.md"
  grep -q "keep last 20 runs" "$BATS_TEST_DIRNAME/../../shared/speculation.md"
}

@test "candidate dir listed in survives-reset notes" {
  grep -q ".forge/plans/candidates" "$BATS_TEST_DIRNAME/../../CLAUDE.md"
}
