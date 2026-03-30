#!/usr/bin/env bats
# Contract tests: agent YAML frontmatter compliance.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

# ---------------------------------------------------------------------------
# 1. All agents have YAML frontmatter (first line is ---)
# ---------------------------------------------------------------------------
@test "agent-frontmatter: all agents start with --- on line 1" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local first_line
    first_line="$(head -1 "$agent_file")"
    if [[ "$first_line" != "---" ]]; then
      failures+=("$(basename "$agent_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Agents missing frontmatter opening ---: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. All agents have name: field
# ---------------------------------------------------------------------------
@test "agent-frontmatter: all agents have name: field" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    if ! grep -qE '^name:' "$agent_file"; then
      failures+=("$(basename "$agent_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Agents missing name: field: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. All agents have description: field
# ---------------------------------------------------------------------------
@test "agent-frontmatter: all agents have description: field" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    if ! grep -qE '^description:' "$agent_file"; then
      failures+=("$(basename "$agent_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Agents missing description: field: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. Pipeline agents: name matches pl-{NNN}-{role} regex
# ---------------------------------------------------------------------------
@test "agent-frontmatter: pipeline agent names match pl-NNN-role pattern" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/pl-*.md; do
    local name_value
    name_value="$(grep -E '^name:' "$agent_file" | head -1 | sed 's/^name:[[:space:]]*//')"
    if ! printf '%s' "$name_value" | grep -qE '^pl-[0-9]{3}-[a-z][a-z0-9-]+$'; then
      failures+=("$(basename "$agent_file"): name='$name_value'")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Pipeline agents with invalid name format: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. Agent name matches filename (without .md)
# ---------------------------------------------------------------------------
@test "agent-frontmatter: name field matches filename" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local expected_name
    expected_name="$(basename "$agent_file" .md)"
    local actual_name
    actual_name="$(grep -E '^name:' "$agent_file" | head -1 | sed 's/^name:[[:space:]]*//')"
    if [[ "$actual_name" != "$expected_name" ]]; then
      failures+=("$(basename "$agent_file"): expected='$expected_name' got='$actual_name'")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Agents with name mismatch: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 6. Review agents have tools: list
# ---------------------------------------------------------------------------
@test "agent-frontmatter: review agents have tools: field" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local basename
    basename="$(basename "$agent_file" .md)"
    # Skip pipeline agents (pl-*)
    [[ "$basename" == pl-* ]] && continue
    # This is a review/cross-cutting agent — must have tools:
    if ! grep -qE '^tools:' "$agent_file"; then
      failures+=("$basename")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Review agents missing tools: field: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 7. Agent count >= 30
# ---------------------------------------------------------------------------
@test "agent-frontmatter: at least 30 agents exist" {
  local count
  count="$(ls "$AGENTS_DIR"/*.md | wc -l | tr -d ' ')"
  if (( count < 30 )); then
    fail "Expected >= 30 agents, found $count"
  fi
}

# ---------------------------------------------------------------------------
# 8. No duplicate agent names
# ---------------------------------------------------------------------------
@test "agent-frontmatter: no duplicate agent names" {
  local names
  names="$(grep -h '^name:' "$AGENTS_DIR"/*.md | sed 's/^name:[[:space:]]*//' | sort)"
  local duplicates
  duplicates="$(printf '%s\n' "$names" | sort | uniq -d)"
  if [[ -n "$duplicates" ]]; then
    fail "Duplicate agent names found: $duplicates"
  fi
}
