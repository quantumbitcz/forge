#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

THIN_LAUNCHERS=(forge-run forge-fix forge-shape forge-sprint bootstrap-project migration)

@test "thin-launcher: all have dispatch instruction" {
  for s in "${THIN_LAUNCHERS[@]}"; do
    run grep -qi 'dispatch\|Agent\|orchestrat\|shaper' "$SKILLS_DIR/$s/SKILL.md"
    assert_success
  done
}

@test "thin-launcher: all have do-nothing-else instruction" {
  for s in "${THIN_LAUNCHERS[@]}"; do
    run grep -qi 'do nothing\|nothing else\|only.*dispatch\|relay' "$SKILLS_DIR/$s/SKILL.md"
    assert_success
  done
}

@test "thin-launcher: forge-run is a thin launcher" {
  local skill="$SKILLS_DIR/forge-run/SKILL.md"
  run grep -qi 'dispatch' "$skill"
  assert_success
}

@test "thin-launcher: none dispatch deleted agents" {
  for s in "${THIN_LAUNCHERS[@]}"; do
    run grep -q 'fg-420' "$SKILLS_DIR/$s/SKILL.md"
    refute_success
  done
}
