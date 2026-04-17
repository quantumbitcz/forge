#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

@test "skill-frontmatter: all skills have SKILL.md" {
  # Phase 1 (v3.0.0) consolidated 42 → 35 skills. Threshold bumped 38 → 35.
  local count=0
  for dir in "$SKILLS_DIR"/*/; do
    [ -f "${dir}SKILL.md" ] || fail "Missing SKILL.md in $dir"
    count=$((count + 1))
  done
  [[ "$count" -ge 35 ]]
}

@test "skill-frontmatter: all skills have name field" {
  for dir in "$SKILLS_DIR"/*/; do
    local skill="${dir}SKILL.md"
    run grep -q '^name:' "$skill"
    assert_success
  done
}

@test "skill-frontmatter: all skill names match directory names" {
  for dir in "$SKILLS_DIR"/*/; do
    local dirname
    dirname=$(basename "$dir")
    local name
    name=$(awk '/^---$/{n++; next} n==1 && /^name:/{sub(/^name: */, ""); print}' "${dir}SKILL.md")
    assert_equal "$name" "$dirname"
  done
}

@test "skill-frontmatter: all skills have description field" {
  for dir in "$SKILLS_DIR"/*/; do
    run grep -q '^description:' "${dir}SKILL.md"
    assert_success
  done
}

@test "skill-frontmatter: all skills start with --- frontmatter marker" {
  for dir in "$SKILLS_DIR"/*/; do
    run head -1 "${dir}SKILL.md"
    assert_output "---"
  done
}

@test "skill-frontmatter: at least 35 skills exist" {
  # Phase 1 (v3.0.0) consolidated 42 → 35 skills. Threshold bumped 40 → 35.
  local count
  count=$(find "$SKILLS_DIR" -name "SKILL.md" | wc -l)
  [[ "$count" -ge 35 ]]
}
