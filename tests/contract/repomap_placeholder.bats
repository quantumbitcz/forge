#!/usr/bin/env bats

@test "fg-100-orchestrator references {{REPO_MAP_PACK}} with BUDGET=8000" {
  grep -q "{{REPO_MAP_PACK:BUDGET=8000" \
    "${BATS_TEST_DIRNAME}/../../agents/fg-100-orchestrator.md"
}

@test "fg-200-planner references {{REPO_MAP_PACK}} with BUDGET=10000" {
  grep -q "{{REPO_MAP_PACK:BUDGET=10000" \
    "${BATS_TEST_DIRNAME}/../../agents/fg-200-planner.md"
}

@test "fg-300-implementer references {{REPO_MAP_PACK}} with BUDGET=4000 per task" {
  grep -q "{{REPO_MAP_PACK:BUDGET=4000" \
    "${BATS_TEST_DIRNAME}/../../agents/fg-300-implementer.md"
}

@test "each integrated agent mentions prompt_compaction.enabled gate" {
  for a in fg-100-orchestrator fg-200-planner fg-300-implementer; do
    grep -q "prompt_compaction" \
      "${BATS_TEST_DIRNAME}/../../agents/${a}.md"
  done
}
