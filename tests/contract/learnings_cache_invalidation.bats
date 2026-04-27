#!/usr/bin/env bats

setup() { DOC="$BATS_TEST_DIRNAME/../../agents/fg-100-orchestrator.md"; }

@test "orchestrator documents learnings-cache invalidation at LEARN" {
  run grep -F "learnings_cache" "$DOC"
  [ "$status" -eq 0 ]
  run grep -F "cache invalidated" "$DOC"
  [ "$status" -eq 0 ]
}
