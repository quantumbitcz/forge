#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

@test "skill-error-handling: pipeline skills have error handling" {
  local pipeline_skills=(forge-run forge-fix forge-review forge-init)
  for s in "${pipeline_skills[@]}"; do
    run grep -qi 'error\|fail\|missing\|not found' "$SKILLS_DIR/$s/SKILL.md"
    assert_success
  done
}

@test "skill-error-handling: graph skill handles missing Neo4j" {
  # Phase 05 Task 4: 5 skills consolidated into /forge-graph with positional subcommands.
  run grep -qi 'docker\|container\|unavailable\|not running' "$SKILLS_DIR/forge-graph/SKILL.md"
  assert_success
}

@test "skill-error-handling: deploy skill has rollback guidance" {
  run grep -qi 'rollback\|revert\|fail' "$SKILLS_DIR/forge-deploy/SKILL.md"
  assert_success
}
