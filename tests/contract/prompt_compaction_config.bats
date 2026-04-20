#!/usr/bin/env bats

@test "preflight-constraints documents prompt_compaction dependency" {
  grep -q "code_graph.prompt_compaction.enabled" \
    "${BATS_TEST_DIRNAME}/../../shared/preflight-constraints.md"
  grep -q "requires.*code_graph.enabled" \
    "${BATS_TEST_DIRNAME}/../../shared/preflight-constraints.md"
}

@test "at least one framework template declares the new block" {
  local found=0
  for f in "${BATS_TEST_DIRNAME}/../../modules/frameworks/"*"/forge-config-template.md"; do
    if grep -q "prompt_compaction:" "$f"; then
      found=1
      break
    fi
  done
  [ "$found" -eq 1 ]
}
