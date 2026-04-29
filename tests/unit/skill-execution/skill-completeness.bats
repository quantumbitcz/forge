#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

# Extract a `### Subcommand: <name>` block from a consolidated SKILL.md and
# count its non-blank content lines (excluding the heading).
_subcommand_lines() {
  local skill_file="$1" name="$2"
  awk -v name="$name" '
    $0 ~ "^### Subcommand: " name "$" { in_block=1; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$skill_file" | grep -c '[^[:space:]]'
}

@test "skill-completeness: forge-admin abort subcommand has >=20 lines of content" {
  local body_lines
  body_lines="$(_subcommand_lines "$SKILLS_DIR/forge-admin/SKILL.md" abort)"
  [[ "$body_lines" -ge 20 ]]
}

@test "skill-completeness: forge-admin recover subcommand has >=20 lines of content" {
  local body_lines
  body_lines="$(_subcommand_lines "$SKILLS_DIR/forge-admin/SKILL.md" recover)"
  [[ "$body_lines" -ge 20 ]]
}

@test "skill-completeness: forge verify subcommand has content" {
  # Post-Mega-B: the verify subcommand is a terse dispatcher; the bulk of
  # build/lint/test orchestration lives in the underlying agents and
  # forge.local.md config. Threshold reflects the consolidated surface.
  local body_lines
  body_lines="$(_subcommand_lines "$SKILLS_DIR/forge/SKILL.md" verify)"
  [[ "$body_lines" -ge 5 ]]
}

@test "skill-completeness: forge-admin compress subcommand has content" {
  local body_lines
  body_lines="$(_subcommand_lines "$SKILLS_DIR/forge-admin/SKILL.md" compress)"
  [[ "$body_lines" -ge 20 ]]
}
