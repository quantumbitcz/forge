#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

@test "skill-frontmatter: all skills have SKILL.md" {
  local count=0
  for dir in "$SKILLS_DIR"/*/; do
    assert [ -f "${dir}SKILL.md" ] "Missing SKILL.md in $dir"
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
    name=$(sed -n 's/^name: *//p' "${dir}SKILL.md")
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
  local count
  count=$(find "$SKILLS_DIR" -name "SKILL.md" | wc -l)
  [[ "$count" -ge 35 ]]
}
