#!/usr/bin/env bats
# Contract assertions for the repo-map A/B eval infra.
# Guards the scenario dir + workflow wiring so future refactors don't
# silently drop the infrastructure.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCENARIO_DIR="${REPO_ROOT}/tests/evals/pipeline/scenarios/11-repo-map-ab"
  WORKFLOW="${REPO_ROOT}/.github/workflows/evals-compaction-ab.yml"
}

@test "scenario prompt.md exists and is non-empty" {
  [ -f "${SCENARIO_DIR}/prompt.md" ]
  [ -s "${SCENARIO_DIR}/prompt.md" ]
}

@test "scenario expected.yaml exists and has id line" {
  [ -f "${SCENARIO_DIR}/expected.yaml" ]
  grep -qE '^id:[[:space:]]+11-repo-map-ab$' "${SCENARIO_DIR}/expected.yaml"
}

@test "scenario expected.yaml declares mode: standard" {
  grep -qE '^mode:[[:space:]]+standard$' "${SCENARIO_DIR}/expected.yaml"
}

@test "scenario expected.yaml declares required_verdict: PASS" {
  grep -qE '^required_verdict:[[:space:]]+PASS$' "${SCENARIO_DIR}/expected.yaml"
}

@test "A/B workflow file exists" {
  [ -f "${WORKFLOW}" ]
}

@test "workflow sets compaction env flag to false in OFF job" {
  grep -q "FORGE_CONFIG_OVERRIDE_CODE_GRAPH_PROMPT_COMPACTION_ENABLED: 'false'" "${WORKFLOW}"
}

@test "workflow sets compaction env flag to true in ON job" {
  grep -q "FORGE_CONFIG_OVERRIDE_CODE_GRAPH_PROMPT_COMPACTION_ENABLED: 'true'" "${WORKFLOW}"
}

@test "workflow defines compaction-off job" {
  grep -qE '^[[:space:]]+compaction-off:' "${WORKFLOW}"
}

@test "workflow defines compaction-on job" {
  grep -qE '^[[:space:]]+compaction-on:' "${WORKFLOW}"
}

@test "workflow defines compare job" {
  grep -qE '^[[:space:]]+compare:' "${WORKFLOW}"
}

@test "workflow is gated off in at least one job" {
  run grep -c 'if: ${{ false }}' "${WORKFLOW}"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "workflow pins actions/checkout@v6" {
  grep -q 'uses: actions/checkout@v6' "${WORKFLOW}"
}

@test "workflow pins actions/setup-python@v6" {
  grep -q 'uses: actions/setup-python@v6' "${WORKFLOW}"
}

@test "workflow pins actions/upload-artifact@v7" {
  grep -q 'uses: actions/upload-artifact@v7' "${WORKFLOW}"
}
