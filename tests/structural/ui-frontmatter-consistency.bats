#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "skills using AskUserQuestion have ui: frontmatter" {
  local failures=0
  for skill_dir in "${PLUGIN_ROOT}"/skills/*/; do
    local skill_file="${skill_dir}SKILL.md"
    [[ -f "$skill_file" ]] || continue
    if grep -q 'AskUserQuestion' "$skill_file"; then
      if ! get_frontmatter "$skill_file" | grep -q '^ui:'; then
        echo "MISSING ui: in $(basename "$skill_dir")" >&2
        failures=$((failures + 1))
      fi
    fi
  done
  assert [ "$failures" -eq 0 ]
}

@test "skills using TaskCreate have ui: with tasks" {
  local failures=0
  for skill_dir in "${PLUGIN_ROOT}"/skills/*/; do
    local skill_file="${skill_dir}SKILL.md"
    [[ -f "$skill_file" ]] || continue
    if grep -q 'TaskCreate' "$skill_file"; then
      if ! get_frontmatter "$skill_file" | grep -q 'tasks.*true'; then
        echo "MISSING ui.tasks in $(basename "$skill_dir")" >&2
        failures=$((failures + 1))
      fi
    fi
  done
  assert [ "$failures" -eq 0 ]
}
