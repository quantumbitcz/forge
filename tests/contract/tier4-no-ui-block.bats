#!/usr/bin/env bats
# Contract test: Tier 4 agents must not have ui: blocks in frontmatter.
# Rationale: Tier 4 = "(none)" per CLAUDE.md. Explicit false adds 48 lines
# of system prompt tokens with zero information.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

# Tier 4 agents per CLAUDE.md: all reviewers, validator, worktree manager, conflict resolver
TIER4_AGENTS=(
  fg-210-validator
  fg-101-worktree-manager
  fg-102-conflict-resolver
  fg-410-code-reviewer
  fg-411-security-reviewer
  fg-412-architecture-reviewer
  fg-413-frontend-reviewer
  fg-416-performance-reviewer
  fg-417-dependency-reviewer
  fg-418-docs-consistency-reviewer
  fg-419-infra-deploy-reviewer
  fg-417-dependency-reviewer
)

# get_frontmatter() provided by test-helpers.bash

@test "tier4-no-ui: Tier 4 agents do not have ui: block in frontmatter" {
  local failures=()
  for agent_name in "${TIER4_AGENTS[@]}"; do
    local agent_file="${AGENTS_DIR}/${agent_name}.md"
    [[ -f "$agent_file" ]] || { failures+=("${agent_name}: file not found"); continue; }
    local frontmatter
    frontmatter="$(get_frontmatter "$agent_file")"
    if echo "$frontmatter" | grep -q "^ui:"; then
      failures+=("${agent_name}: has ui: block (Tier 4 should have none)")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Tier 4 ui: block violations: ${#failures[@]} agents"
  fi
}

@test "tier4-no-ui: all listed Tier 4 agent files exist" {
  local missing=()
  for agent_name in "${TIER4_AGENTS[@]}"; do
    [[ -f "${AGENTS_DIR}/${agent_name}.md" ]] || missing+=("${agent_name}")
  done
  if (( ${#missing[@]} > 0 )); then
    printf '%s\n' "${missing[@]}"
    fail "Missing Tier 4 agent files: ${#missing[@]}"
  fi
}
