#!/usr/bin/env bats
# Validates all skill files have required structural elements.

load '../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"

@test "skill-descriptions: all skills have description in frontmatter" {
  local missing=0
  for skill_dir in "$SKILLS_DIR"/forge-*/; do
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    if ! sed -n '2,/^---$/p' "$skill_file" | grep -q '^description:'; then
      echo "MISSING: $skill_file — no description in frontmatter"
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "skill-descriptions: all descriptions include 'Use when' clause" {
  local weak=0
  for skill_dir in "$SKILLS_DIR"/forge-*/; do
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    local desc
    desc=$(sed -n '2,/^---$/p' "$skill_file" | grep '^description:' | head -1)
    if ! echo "$desc" | grep -qi 'Use when'; then
      echo "WEAK: $skill_file — description lacks 'Use when' clause"
      weak=$((weak + 1))
    fi
  done
  [ "$weak" -eq 0 ]
}

@test "skill-descriptions: all skills have allowed-tools in frontmatter" {
  local missing=0
  for skill_dir in "$SKILLS_DIR"/forge-*/; do
    local skill_file="$skill_dir/SKILL.md"
    [ -f "$skill_file" ] || continue
    if ! sed -n '2,/^---$/p' "$skill_file" | grep -q '^allowed-tools:'; then
      echo "MISSING: $skill_file — no allowed-tools in frontmatter"
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -eq 0 ]
}

