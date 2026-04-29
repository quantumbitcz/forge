#!/usr/bin/env bats
# Contract: All skills must have valid structure.

load '../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"

# ---------------------------------------------------------------------------
# 1. Every skill has a SKILL.md
# ---------------------------------------------------------------------------
@test "skill-frontmatter: every skill directory has SKILL.md" {
  local missing=()
  for d in "$SKILLS_DIR"/*/; do
    [ -d "$d" ] || continue
    local name
    name="$(basename "$d")"
    if [ ! -f "$d/SKILL.md" ]; then
      missing+=("$name")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    fail "Skills missing SKILL.md: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. Every SKILL.md has name: in frontmatter
# ---------------------------------------------------------------------------
@test "skill-frontmatter: every SKILL.md has name field" {
  local missing=()
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$f" ] || continue
    local skill_dir
    skill_dir="$(basename "$(dirname "$f")")"
    if ! grep -q '^name:' "$f"; then
      missing+=("$skill_dir")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    fail "Skills missing name: field: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. Every SKILL.md has description: in frontmatter
# ---------------------------------------------------------------------------
@test "skill-frontmatter: every SKILL.md has description field" {
  local missing=()
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$f" ] || continue
    local skill_dir
    skill_dir="$(basename "$(dirname "$f")")"
    if ! grep -q '^description:' "$f"; then
      missing+=("$skill_dir")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    fail "Skills missing description: field: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. Skill name matches directory name
# ---------------------------------------------------------------------------
@test "skill-frontmatter: skill name matches directory name" {
  local mismatches=()
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$f" ] || continue
    local dir_name
    dir_name="$(basename "$(dirname "$f")")"
    local skill_name
    skill_name="$(grep -m1 '^name:' "$f" | sed 's/^name:[[:space:]]*//')"
    if [ "$skill_name" != "$dir_name" ]; then
      mismatches+=("$dir_name (name: $skill_name)")
    fi
  done
  if [ ${#mismatches[@]} -gt 0 ]; then
    fail "Skill name mismatches: ${mismatches[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. At least 3 skills exist. Post-Mega-B consolidation collapsed the 28-skill
#    surface into 3 top-level skills (/forge, /forge-ask, /forge-admin).
# ---------------------------------------------------------------------------
@test "skill-frontmatter: at least 3 skills exist" {
  local count=0
  for d in "$SKILLS_DIR"/*/; do
    [ -d "$d" ] && count=$(( count + 1 ))
  done
  # Post-Mega-B consolidation target: 3.
  if (( count < 3 )); then
    fail "Expected >= 3 skills, found $count"
  fi
}

# ---------------------------------------------------------------------------
# 6. No duplicate skill names
# ---------------------------------------------------------------------------
@test "skill-frontmatter: no duplicate skill names" {
  local names
  names="$(grep -h '^name:' "$SKILLS_DIR"/*/SKILL.md 2>/dev/null | sed 's/^name:[[:space:]]*//' | sort)"
  local dupes
  dupes="$(echo "$names" | uniq -d)"
  if [ -n "$dupes" ]; then
    fail "Duplicate skill names found: $dupes"
  fi
}

# ---------------------------------------------------------------------------
# 7. Skill descriptions are non-empty
# ---------------------------------------------------------------------------
@test "skill-frontmatter: skill descriptions are non-empty" {
  local empty=()
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$f" ] || continue
    local skill_dir
    skill_dir="$(basename "$(dirname "$f")")"
    local desc
    desc="$(grep -m1 '^description:' "$f" | sed 's/^description:[[:space:]]*//')"
    if [ -z "$desc" ]; then
      empty+=("$skill_dir")
    fi
  done
  if [ ${#empty[@]} -gt 0 ]; then
    fail "Skills with empty description: ${empty[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 8. Every SKILL.md has allowed-tools: in frontmatter
# ---------------------------------------------------------------------------
@test "skill-frontmatter: every SKILL.md has allowed-tools field" {
  local missing=()
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$f" ] || continue
    local skill_dir
    skill_dir="$(basename "$(dirname "$f")")"
    if ! grep -q '^allowed-tools:' "$f"; then
      missing+=("$skill_dir")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    fail "Skills missing allowed-tools: field: ${missing[*]}"
  fi
}
