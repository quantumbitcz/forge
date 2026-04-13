#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

@test "skill-completeness: forge-abort has >=20 lines of content" {
  local body_lines
  body_lines=$(sed '1,/^---$/d' "$SKILLS_DIR/forge-abort/SKILL.md" | sed '1,/^---$/d' | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 20 ]]
}

@test "skill-completeness: forge-resume has >=20 lines of content" {
  local body_lines
  body_lines=$(sed '1,/^---$/d' "$SKILLS_DIR/forge-resume/SKILL.md" | sed '1,/^---$/d' | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 20 ]]
}

@test "skill-completeness: forge-diagnose has >=20 lines of content" {
  local body_lines
  body_lines=$(sed '1,/^---$/d' "$SKILLS_DIR/forge-diagnose/SKILL.md" | sed '1,/^---$/d' | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 20 ]]
}

@test "skill-completeness: forge-reset has >=20 lines of content" {
  local body_lines
  body_lines=$(sed '1,/^---$/d' "$SKILLS_DIR/forge-reset/SKILL.md" | sed '1,/^---$/d' | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 20 ]]
}

@test "skill-completeness: verify skill has content" {
  local body_lines
  body_lines=$(sed '1,/^---$/d' "$SKILLS_DIR/verify/SKILL.md" | sed '1,/^---$/d' | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 10 ]]
}

@test "skill-completeness: forge-caveman skill has content" {
  local body_lines
  body_lines=$(sed '1,/^---$/d' "$SKILLS_DIR/forge-caveman/SKILL.md" | sed '1,/^---$/d' | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 20 ]]
}
