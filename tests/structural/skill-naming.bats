#!/usr/bin/env bats
# Structural test: all skill directories use the forge namespace.
#
# Post-Mega-B (skill consolidation): the top-level write surface lives at
# `skills/forge/` (no hyphen) — the universal entry. Read-only and admin
# surfaces are `skills/forge-ask/` and `skills/forge-admin/`. All other
# legacy `forge-*` skills were retired in favour of subcommands under
# these three. Accept both `forge` (exact) and `forge-*` as valid.

load '../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"

@test "skill-naming: all skill directories have forge- prefix" {
  local violations=()
  for d in "$SKILLS_DIR"/*/; do
    [ -d "$d" ] || continue
    local name
    name="$(basename "$d")"
    if [[ "$name" != forge && "$name" != forge-* ]]; then
      violations+=("$name")
    fi
  done
  if [ ${#violations[@]} -gt 0 ]; then
    fail "Skills outside the forge namespace: ${violations[*]}"
  fi
}

@test "skill-naming: skill name: field matches forge- prefix convention" {
  local violations=()
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$f" ] || continue
    local skill_name
    skill_name="$(grep -m1 '^name:' "$f" | sed 's/^name:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')"
    if [[ "$skill_name" != forge && "$skill_name" != forge-* ]]; then
      violations+=("$skill_name")
    fi
  done
  if [ ${#violations[@]} -gt 0 ]; then
    fail "Skill names outside the forge namespace: ${violations[*]}"
  fi
}
