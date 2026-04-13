#!/usr/bin/env bats
# Contract tests: skill quality compliance per Q01 spec.

load '../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"

# ---------------------------------------------------------------------------
# 1. All skills have YAML frontmatter with description field
# ---------------------------------------------------------------------------
@test "skill-quality: all skills have description: field in frontmatter" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    if ! grep -qE '^description:' "$skill_file"; then
      failures+=("$(basename "$skill_dir")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills missing description: field: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. All descriptions include "Use when" trigger clause
# ---------------------------------------------------------------------------
@test "skill-quality: all descriptions include 'Use when' trigger clause" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    if ! grep -qE '^description:.*[Uu]se when' "$skill_file"; then
      failures+=("$(basename "$skill_dir")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills missing 'Use when' in description: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. All descriptions are at least 80 characters
# ---------------------------------------------------------------------------
@test "skill-quality: all descriptions are at least 80 characters" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    local desc
    desc="$(grep -E '^description:' "$skill_file" | head -1 | sed 's/^description:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')"
    if (( ${#desc} < 80 )); then
      failures+=("$(basename "$skill_dir") (${#desc} chars)")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills with short descriptions (<80 chars): ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. All descriptions use double-quoted YAML strings
# ---------------------------------------------------------------------------
@test "skill-quality: all descriptions use double-quoted YAML strings" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    local desc_line
    desc_line="$(grep -E '^description:' "$skill_file" | head -1)"
    # Should match description: "..."
    if ! echo "$desc_line" | grep -qE '^description:[[:space:]]*"'; then
      failures+=("$(basename "$skill_dir")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills not using double-quoted descriptions: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. All skills have ## Prerequisites section
# ---------------------------------------------------------------------------
@test "skill-quality: all skills have ## Prerequisites section" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    if ! grep -qE '^## Prerequisites' "$skill_file"; then
      failures+=("$(basename "$skill_dir")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills missing ## Prerequisites: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 6. All skills have ## Instructions section (not "What to do")
# ---------------------------------------------------------------------------
@test "skill-quality: all skills have ## Instructions (not 'What to do')" {
  local failures=()
  local old_header=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    if ! grep -qE '^## Instructions' "$skill_file"; then
      failures+=("$(basename "$skill_dir")")
    fi
    if grep -qE '^## What to do' "$skill_file"; then
      old_header+=("$(basename "$skill_dir")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills missing ## Instructions: ${failures[*]}"
  fi
  if (( ${#old_header[@]} > 0 )); then
    fail "Skills still using '## What to do': ${old_header[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 7. All skills have ## Error Handling section
# ---------------------------------------------------------------------------
@test "skill-quality: all skills have ## Error Handling section" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    if ! grep -qE '^## Error Handling' "$skill_file"; then
      failures+=("$(basename "$skill_dir")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills missing ## Error Handling: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 8. All skills have ## See Also section
# ---------------------------------------------------------------------------
@test "skill-quality: all skills have ## See Also section" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    if ! grep -qE '^## See Also' "$skill_file"; then
      failures+=("$(basename "$skill_dir")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills missing ## See Also: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 9. See Also references point to valid skill directories
# ---------------------------------------------------------------------------
@test "skill-quality: See Also references point to valid skills" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    # Extract /skill-name references from See Also section
    local in_see_also=false
    while IFS= read -r line; do
      if [[ "$line" == "## See Also"* ]]; then
        in_see_also=true
        continue
      fi
      if [[ "$line" == "## "* ]] && $in_see_also; then
        break
      fi
      if $in_see_also; then
        # Extract /skill-name patterns
        local refs
        refs="$(echo "$line" | grep -oE '/[a-z][-a-z]*' || true)"
        for ref in $refs; do
          local ref_name="${ref#/}"
          if [[ ! -d "$SKILLS_DIR/$ref_name" ]]; then
            failures+=("$(basename "$skill_dir") references non-existent /$ref_name")
          fi
        done
      fi
    done < "$skill_file"
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Invalid See Also references: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 10. No skills use pipe (|) or folded (>) YAML style for description
# ---------------------------------------------------------------------------
@test "skill-quality: no skills use pipe or folded YAML for description" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    local desc_line
    desc_line="$(grep -E '^description:' "$skill_file" | head -1)"
    if echo "$desc_line" | grep -qE '^description:[[:space:]]*[|>]'; then
      failures+=("$(basename "$skill_dir")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills using pipe/folded YAML for description: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 11. Minimum skill count guard
# ---------------------------------------------------------------------------
@test "skill-quality: minimum skill count is met" {
  local count=0
  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -f "$skill_dir/SKILL.md" ]] && (( ++count ))
  done
  if (( count < 35 )); then
    fail "Expected at least 35 skills, found $count"
  fi
}

# ---------------------------------------------------------------------------
# 12. All skills have name: field matching directory name
# ---------------------------------------------------------------------------
@test "skill-quality: skill name matches directory name" {
  local failures=()
  for skill_dir in "$SKILLS_DIR"/*/; do
    local skill_file="$skill_dir/SKILL.md"
    [[ -f "$skill_file" ]] || continue
    local dir_name
    dir_name="$(basename "$skill_dir")"
    local skill_name
    skill_name="$(grep -E '^name:' "$skill_file" | head -1 | sed 's/^name:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')"
    if [[ "$skill_name" != "$dir_name" ]]; then
      failures+=("$dir_name (name: $skill_name)")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skills with name/directory mismatch: ${failures[*]}"
  fi
}
