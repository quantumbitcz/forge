#!/usr/bin/env bats
# Contract test: Tier 1 agents must have <example> blocks in description.
# Per CLAUDE.md: "Tier 1 (entry, 6): description + example."

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

TIER1_AGENTS=(
  fg-010-shaper
  fg-015-scope-decomposer
  fg-050-project-bootstrapper
  fg-090-sprint-orchestrator
  fg-160-migration-planner
  fg-200-planner
)

# get_frontmatter() provided by test-helpers.bash

@test "tier1-examples: all Tier 1 agents have <example> blocks in description" {
  local failures=()
  for agent_name in "${TIER1_AGENTS[@]}"; do
    local agent_file="${AGENTS_DIR}/${agent_name}.md"
    [[ -f "$agent_file" ]] || { failures+=("${agent_name}: file not found"); continue; }
    local frontmatter
    frontmatter="$(get_frontmatter "$agent_file")"
    if ! echo "$frontmatter" | grep -q "<example>"; then
      failures+=("${agent_name}: missing <example> block in description")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Tier 1 example violations: ${#failures[@]} agents"
  fi
}

@test "tier1-examples: all listed Tier 1 agent files exist" {
  local missing=()
  for agent_name in "${TIER1_AGENTS[@]}"; do
    [[ -f "${AGENTS_DIR}/${agent_name}.md" ]] || missing+=("${agent_name}")
  done
  if (( ${#missing[@]} > 0 )); then
    printf '%s\n' "${missing[@]}"
    fail "Missing Tier 1 agent files: ${#missing[@]}"
  fi
}
