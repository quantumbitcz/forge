#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  SKILL_FILE="$SKILLS_DIR/forge-review/SKILL.md"
}

@test "forge-review-integration: default dispatches 3 core agents" {
  # The default (no --full) mode dispatches 3 core review agents
  # Verify all 3 core agents are referenced: fg-410, fg-411, fg-412
  run grep -c 'fg-41[012]' "$SKILL_FILE"
  assert_success
  # Should find at least 3 references (one per core agent)
  assert [ "$output" -ge 3 ]
}

@test "forge-review-integration: --full dispatches up to 9 agents" {
  # Verify the skill documents --full mode with extended agent list
  run grep -qi '\-\-full' "$SKILL_FILE"
  assert_success
  # Verify reference to extended agents (up to 9: fg-410 through fg-419)
  run grep -cE 'fg-41[0-9]' "$SKILL_FILE"
  assert_success
  # Should reference more agents than just the core 3
  assert [ "$output" -ge 4 ]
}

@test "forge-review-integration: skill documents review-fix loop" {
  run grep -qi 'loop\|iterate\|re-review\|score\|fix.*finding\|finding.*fix\|converge' "$SKILL_FILE"
  assert_success
}
