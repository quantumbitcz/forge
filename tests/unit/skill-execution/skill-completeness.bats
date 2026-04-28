#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

@test "skill-completeness: forge-abort has >=20 lines of content" {
  local body_lines
  body_lines=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$SKILLS_DIR/forge-admin abort/SKILL.md" | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 20 ]]
}

@test "skill-completeness: forge-recover has >=20 lines of content" {
  local body_lines
  body_lines=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$SKILLS_DIR/forge-admin recover/SKILL.md" | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 20 ]]
}

@test "skill-completeness: verify skill has content" {
  local body_lines
  body_lines=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$SKILLS_DIR/forge verify/SKILL.md" | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 10 ]]
}

@test "skill-completeness: forge-compress skill has content" {
  local body_lines
  body_lines=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2' "$SKILLS_DIR/forge-admin compress/SKILL.md" | grep -c '[^[:space:]]')
  [[ "$body_lines" -ge 20 ]]
}
