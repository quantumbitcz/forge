#!/usr/bin/env bats
# Contract tests: agent UI frontmatter consistency.
# Validates that ui: declarations match tools: lists and vice versa.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

# Orchestrator phase files are loaded as includes (no frontmatter)
is_orch_phase_file() {
  local name
  name="$(basename "$1" .md)"
  [[ "$name" == fg-100-orchestrator-boot ]] || \
  [[ "$name" == fg-100-orchestrator-execute ]] || \
  [[ "$name" == fg-100-orchestrator-ship ]]
}

# ---------------------------------------------------------------------------
# Helper: extract ui.X value from frontmatter (returns "true", "false", or "")
# ---------------------------------------------------------------------------
get_ui_field() {
  local file="$1" field="$2"
  awk '/^---$/{n++; next} n==1{print}' "$file" | grep "^  ${field}:" | awk '{print $2}' | tr -d ' '
}

# Helper: check if tool is in tools list
has_tool() {
  local file="$1" tool="$2"
  grep -q "'${tool}'" "$file" || grep -q "\"${tool}\"" "$file"
}

# ---------------------------------------------------------------------------
# 1. Agents with ui.tasks: true must have TaskCreate and TaskUpdate in tools
# ---------------------------------------------------------------------------
@test "ui-frontmatter: ui.tasks: true requires TaskCreate + TaskUpdate in tools" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    is_orch_phase_file "$agent_file" && continue
    local val
    val="$(get_ui_field "$agent_file" "tasks")"
    if [[ "$val" == "true" ]]; then
      if ! has_tool "$agent_file" "TaskCreate" || ! has_tool "$agent_file" "TaskUpdate"; then
        failures+=("$(basename "$agent_file"): ui.tasks: true but missing TaskCreate/TaskUpdate in tools")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter inconsistency: ${#failures[@]} agents"
  fi
}

# ---------------------------------------------------------------------------
# 2. Agents with ui.ask: true must have AskUserQuestion in tools
# ---------------------------------------------------------------------------
@test "ui-frontmatter: ui.ask: true requires AskUserQuestion in tools" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    is_orch_phase_file "$agent_file" && continue
    local val
    val="$(get_ui_field "$agent_file" "ask")"
    if [[ "$val" == "true" ]]; then
      if ! has_tool "$agent_file" "AskUserQuestion"; then
        failures+=("$(basename "$agent_file"): ui.ask: true but missing AskUserQuestion in tools")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter inconsistency: ${#failures[@]} agents"
  fi
}

# ---------------------------------------------------------------------------
# 3. Agents with ui.plan_mode: true must have EnterPlanMode + ExitPlanMode
# ---------------------------------------------------------------------------
@test "ui-frontmatter: ui.plan_mode: true requires EnterPlanMode + ExitPlanMode in tools" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    is_orch_phase_file "$agent_file" && continue
    local val
    val="$(get_ui_field "$agent_file" "plan_mode")"
    if [[ "$val" == "true" ]]; then
      if ! has_tool "$agent_file" "EnterPlanMode" || ! has_tool "$agent_file" "ExitPlanMode"; then
        failures+=("$(basename "$agent_file"): ui.plan_mode: true but missing EnterPlanMode/ExitPlanMode in tools")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter inconsistency: ${#failures[@]} agents"
  fi
}

# ---------------------------------------------------------------------------
# 4. Reverse check: agents with TaskCreate in tools must have ui.tasks: true
# ---------------------------------------------------------------------------
@test "ui-frontmatter: agents with TaskCreate in tools must have ui.tasks: true" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    is_orch_phase_file "$agent_file" && continue
    if has_tool "$agent_file" "TaskCreate"; then
      local val
      val="$(get_ui_field "$agent_file" "tasks")"
      if [[ "$val" != "true" ]]; then
        failures+=("$(basename "$agent_file"): has TaskCreate in tools but ui.tasks is not true")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter drift: ${#failures[@]} agents"
  fi
}

@test "ui-frontmatter: agents with AskUserQuestion in tools must have ui.ask: true" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    is_orch_phase_file "$agent_file" && continue
    if has_tool "$agent_file" "AskUserQuestion"; then
      local val
      val="$(get_ui_field "$agent_file" "ask")"
      if [[ "$val" != "true" ]]; then
        failures+=("$(basename "$agent_file"): has AskUserQuestion in tools but ui.ask is not true")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter drift: ${#failures[@]} agents"
  fi
}

@test "ui-frontmatter: agents with EnterPlanMode in tools must have ui.plan_mode: true" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    is_orch_phase_file "$agent_file" && continue
    if has_tool "$agent_file" "EnterPlanMode"; then
      local val
      val="$(get_ui_field "$agent_file" "plan_mode")"
      if [[ "$val" != "true" ]]; then
        failures+=("$(basename "$agent_file"): has EnterPlanMode in tools but ui.plan_mode is not true")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter drift: ${#failures[@]} agents"
  fi
}
