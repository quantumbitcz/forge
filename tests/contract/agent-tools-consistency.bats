#!/usr/bin/env bats
# Contract tests: agent tools list consistency.
# Verifies that agents have the tools they reference in their body text.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

# Helper: extract tools from agent frontmatter (handles both inline and multi-line YAML)
get_agent_tools() {
  local file="$1"
  local inline
  inline=$(grep '^tools:.*\[' "$file" | head -1 | sed "s/tools:[[:space:]]*//; s/\[//; s/\]//; s/'//g; s/\"//g")
  if [[ -n "$inline" ]]; then
    echo "$inline"
    return
  fi
  awk '/^tools:/{found=1; next} found && /^  - /{t=$0; sub(/^  - /,"",t); printf "%s,", t; next} found && !/^  - /{exit}' "$file"
}

# Helper: extract agent body (everything after frontmatter closing ---)
get_agent_body() {
  awk '/^---/{c++; next} c>=2{print}' "$1"
}

# ---------------------------------------------------------------------------
# 1. Agents that use Agent tool in body text have it in tools list
# ---------------------------------------------------------------------------
@test "agent-tools: agents dispatching sub-agents have Agent in tools" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local name
    name="$(basename "$agent_file" .md)"
    local tools
    tools="$(get_agent_tools "$agent_file")"

    # Skip if agent already has Agent in tools
    if echo "$tools" | grep -q "Agent"; then
      continue
    fi

    # Check body (after frontmatter) for dispatch patterns that require Agent tool
    local body
    body=$(get_agent_body "$agent_file")

    # Pattern: "Dispatch <agent-name>" in imperative context (not "is dispatched" or "dispatches you")
    if echo "$body" | grep -qE "^[0-9]+\.\s+\*?\*?Dispatch\b|dispatch (pre-push|sub-agent|exploration|UI agent)" ; then
      failures+=("$name: body references dispatching but tools missing Agent")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Tool-dispatch mismatch: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. Agents that reference context7 MCP have it in tools list
# ---------------------------------------------------------------------------
@test "agent-tools: agents using context7 have MCP tools in tools list" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local name
    name="$(basename "$agent_file" .md)"
    local tools
    tools="$(get_agent_tools "$agent_file")"

    # Check body for context7 usage (resolve-library-id or query-docs)
    local body
    body=$(get_agent_body "$agent_file")

    # Skip agents that explicitly disclaim MCP usage
    if echo "$body" | grep -qiE "do not directly use MCPs|does not use MCPs"; then
      continue
    fi

    # Look for ACTIVE context7 usage: "use context7", "use it to verify", "resolve-library-id", "query-docs"
    if echo "$body" | grep -qiE "use (context7|it to verify).*context7|Context7 MCP is available, use|resolve-library-id|query-docs"; then
      if ! echo "$tools" | grep -q "context7"; then
        failures+=("$name: actively uses context7 but tools list missing MCP tools")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Context7 tool mismatch: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. Agents that reference Skill invocation have Skill in tools list
# ---------------------------------------------------------------------------
@test "agent-tools: agents invoking skills have Skill in tools list" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local name
    name="$(basename "$agent_file" .md)"
    local tools
    tools="$(get_agent_tools "$agent_file")"

    # Skip if agent already has Skill in tools
    if echo "$tools" | grep -q "Skill"; then
      continue
    fi

    # Check body for skill dispatch patterns
    local body
    body=$(get_agent_body "$agent_file")

    # Match active dispatch of a named skill (e.g., "dispatch claude-md-management:revise-claude-md")
    # Exclude passive references like "dispatch the orchestrator" or "provided by the pipeline-run skill"
    if echo "$body" | grep -qE "dispatch it with|invoke via.*Skill tool|dispatch.*revise-claude-md|dispatch.*claude-md-management"; then
      failures+=("$name: body references invoking skills but tools missing Skill")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Skill tool mismatch: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. Planning agents have EnterPlanMode/ExitPlanMode in tools list
# ---------------------------------------------------------------------------
@test "agent-tools: planning agents have EnterPlanMode and ExitPlanMode tools" {
  local planning_agents=(pl-200-planner pl-010-shaper pl-160-migration-planner pl-050-project-bootstrapper)
  local failures=()
  for agent_name in "${planning_agents[@]}"; do
    local agent_file="$AGENTS_DIR/${agent_name}.md"
    [[ -f "$agent_file" ]] || { failures+=("$agent_name: file not found"); continue; }
    local tools
    tools="$(get_agent_tools "$agent_file")"
    if ! echo "$tools" | grep -q "EnterPlanMode"; then
      failures+=("$agent_name: missing EnterPlanMode")
    fi
    if ! echo "$tools" | grep -q "ExitPlanMode"; then
      failures+=("$agent_name: missing ExitPlanMode")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "PlanMode tool mismatch: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. All agents with Agent in tools actually dispatch something
# ---------------------------------------------------------------------------
@test "agent-tools: agents with Agent tool actually dispatch sub-agents" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local name
    name="$(basename "$agent_file" .md)"
    local tools
    tools="$(get_agent_tools "$agent_file")"

    # Only check agents that have Agent in tools
    if ! echo "$tools" | grep -q "Agent"; then
      continue
    fi

    # Check body for dispatch-related content
    local body
    body=$(get_agent_body "$agent_file")

    if ! echo "$body" | grep -qiE "dispatch|sub-agent|batch|concurrent|parallel.*agent"; then
      failures+=("$name: has Agent tool but body never references dispatching")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Unused Agent tool: ${failures[*]}"
  fi
}
