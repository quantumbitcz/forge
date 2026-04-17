#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

@test "skill-prerequisites: all pipeline skills document prerequisites" {
  local pipeline_skills=(forge-run forge-fix forge-shape forge-sprint forge-review forge-init)
  for s in "${pipeline_skills[@]}"; do
    run grep -qi 'prerequisit\|before\|require\|must\|STOP' "$SKILLS_DIR/$s/SKILL.md"
    assert_success
  done
}

@test "skill-prerequisites: forge-init checks for existing config" {
  run grep -qi 'forge.local\|existing\|already' "$SKILLS_DIR/forge-init/SKILL.md"
  assert_success
}

@test "skill-prerequisites: forge-recover checks for state.json" {
  run grep -qi 'state\.json\|checkpoint\|aborted' "$SKILLS_DIR/forge-recover/SKILL.md"
  assert_success
}

@test "skill-prerequisites: deploy checks for dirty tree" {
  run grep -qi 'dirty\|uncommit\|clean' "$SKILLS_DIR/forge-deploy/SKILL.md"
  assert_success
}
