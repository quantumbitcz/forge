#!/usr/bin/env bats
# Contract test: agent-registry.md must list every agent file and vice versa.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"
REGISTRY="$PLUGIN_ROOT/shared/agent-registry.md"

@test "agent-registry: registry file exists" {
  [[ -f "$REGISTRY" ]]
}

@test "agent-registry: every agent file has a registry entry" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/fg-*.md; do
    local name
    name="$(basename "$agent_file" .md)"
    grep -q "$name" "$REGISTRY" || failures+=("$name: in agents/ but not in registry")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Agents missing from registry: ${#failures[@]}"
  fi
}

@test "agent-registry: every registry entry has an agent file" {
  local failures=()
  # Extract agent IDs from registry table (lines matching fg-NNN-name pattern)
  while IFS= read -r agent_id; do
    [[ -f "${AGENTS_DIR}/${agent_id}.md" ]] || failures+=("${agent_id}: in registry but no agent file")
  done < <(grep -oE 'fg-[0-9]+-[a-z0-9-]+' "$REGISTRY" | sort -u)

  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Registry entries without agent files: ${#failures[@]}"
  fi
}
