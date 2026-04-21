#!/usr/bin/env bats
# Contract tests: agent UI frontmatter consistency.
# Validates that ui: declarations match tools: lists and vice versa.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

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

# ---------------------------------------------------------------------------
# Phase 1 note: the previous skill-level "ui: frontmatter on skills using
# AskUserQuestion / TaskCreate" assertions were removed. `ui:` is an agent
# frontmatter concept (see shared/agent-ui.md); skills do not uniformly carry
# ui: blocks — they can declare UI capabilities via the skill contract
# (shared/skill-contract.md). Agent-side assertions below remain authoritative.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 5 new Phase 1 assertions (plan Task 18 Step 2)
# ---------------------------------------------------------------------------

@test "every non-Tier-4 agent has explicit ui: block; every Tier-4 agent omits ui:" {
  # Contract tightening: Tier-4 (silent) agents MUST omit ui: entirely.
  # Tier-4 list is sourced from shared/agent-role-hierarchy.md §"Tier 4 — None (Silent)".
  local tier4=(
    fg-101-worktree-manager
    fg-102-conflict-resolver
    fg-205-planning-critic
    fg-410-code-reviewer
    fg-411-security-reviewer
    fg-412-architecture-reviewer
    fg-413-frontend-reviewer
    fg-414-license-reviewer
    fg-416-performance-reviewer
    fg-417-dependency-reviewer
    fg-418-docs-consistency-reviewer
    fg-419-infra-deploy-reviewer
    fg-510-mutation-analyzer
  )

  # Build a lookup
  declare -A is_tier4
  for a in "${tier4[@]}"; do is_tier4[$a]=1; done

  local failures=()
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    local base
    base="$(basename "$f" .md)"
    local has_ui
    if grep -q "^ui:" "$f"; then has_ui=1; else has_ui=0; fi

    if [[ -n "${is_tier4[$base]:-}" ]]; then
      # Tier-4 MUST omit ui:
      if (( has_ui == 1 )); then
        failures+=("$base: Tier-4 agent must omit ui: block (found ui:)")
      fi
    else
      # Non-Tier-4 MUST have ui:
      if (( has_ui == 0 )); then
        failures+=("$base: non-Tier-4 agent must have explicit ui: block (missing)")
      fi
    fi
  done

  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "ui: block contract violations: ${#failures[@]}"
  fi
}

@test "no agent uses ui.tier shortcut" {
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    if awk '/^ui:/{flag=1; next} flag && /^[a-z]/{flag=0} flag' "$f" | grep -q "^ *tier:"; then
      echo "ui.tier shortcut found in $f"; return 1
    fi
  done
}

@test "every agent has a color: field" {
  for f in "$PLUGIN_ROOT"/agents/fg-*.md; do
    grep -q "^color:" "$f" || { echo "Missing color: $f"; return 1; }
  done
}

@test "cluster-scoped color uniqueness holds" {
  # Cluster → members mapping sourced from shared/agent-colors.md §2
  declare -A clusters
  clusters["pre-pipeline"]="fg-010 fg-015 fg-020 fg-050 fg-090"
  clusters["orch"]="fg-100 fg-101 fg-102 fg-103"
  clusters["preflight"]="fg-130 fg-135 fg-140 fg-150"
  clusters["plan"]="fg-160 fg-200 fg-205 fg-210 fg-250"
  clusters["impl"]="fg-300 fg-310 fg-320 fg-350"
  clusters["review"]="fg-400 fg-410 fg-411 fg-412 fg-413 fg-416 fg-417 fg-418 fg-419"
  clusters["verify"]="fg-500 fg-505 fg-510 fg-515"
  clusters["ship"]="fg-590 fg-600 fg-610 fg-620 fg-650"
  clusters["learn"]="fg-700 fg-710"

  local bad=0
  for cluster in "${!clusters[@]}"; do
    local colors=""
    for member in ${clusters[$cluster]}; do
      local c
      c=$(grep -h "^color:" "$PLUGIN_ROOT"/agents/${member}*.md 2>/dev/null | head -1 | awk '{print $2}')
      colors="$colors $c"
    done
    local distinct total
    distinct=$(echo "$colors" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
    total=$(echo "$colors" | wc -w | tr -d ' ')
    if [ "$distinct" != "$total" ]; then
      echo "Cluster $cluster has collision: $colors"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "Tier 1/2 agents contain User-interaction examples section" {
  local tier12=(fg-010 fg-015 fg-020 fg-050 fg-090 fg-100 fg-103 fg-160 fg-200 fg-210 fg-400 fg-500 fg-600 fg-710)
  for agent in "${tier12[@]}"; do
    local f
    f=$(ls "$PLUGIN_ROOT"/agents/${agent}*.md 2>/dev/null | head -1)
    [ -n "$f" ] || { echo "Missing agent: $agent"; return 1; }
    grep -q "^## User-interaction examples" "$f" \
      || { echo "Missing User-interaction examples section: $f"; return 1; }
    grep -q '"question":' "$f" \
      || { echo "No AskUserQuestion JSON payload found in: $f"; return 1; }
  done
}
