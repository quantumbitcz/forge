#!/usr/bin/env bats
# Contract tests: mode overlay validation

load '../helpers/test-helpers'

MODES_DIR="$PLUGIN_ROOT/shared/modes"
AGENTS_DIR="$PLUGIN_ROOT/agents"
EXPECTED_MODES=(standard bugfix migration bootstrap testing refactor performance)

@test "mode-overlay: all 7 mode files exist" {
  local missing=()
  for mode in "${EXPECTED_MODES[@]}"; do
    [[ -f "$MODES_DIR/${mode}.md" ]] || missing+=("$mode")
  done
  [[ ${#missing[@]} -eq 0 ]] || fail "Missing mode files: ${missing[*]}"
}

@test "mode-overlay: all modes have valid YAML frontmatter" {
  for mode in "${EXPECTED_MODES[@]}"; do
    local file="$MODES_DIR/${mode}.md"
    local first_line; first_line=$(head -1 "$file")
    [[ "$first_line" == "---" ]] || fail "${mode}.md does not start with YAML frontmatter"
    local mode_field
    mode_field=$(sed -n '2,/^---$/p' "$file" | grep -E '^mode:' | head -1 | sed 's/mode:[[:space:]]*//')
    [[ "$mode_field" == "$mode" ]] || fail "${mode}.md mode: field is '$mode_field', expected '$mode'"
  done
}

@test "mode-overlay: agent references in batch_override exist" {
  local missing=()
  for mode in "${EXPECTED_MODES[@]}"; do
    local file="$MODES_DIR/${mode}.md"
    local agents; agents=$(grep -oE 'fg-[0-9]+-[a-z-]+' "$file" 2>/dev/null || true)
    for agent in $agents; do
      [[ -f "$AGENTS_DIR/${agent}.md" ]] || missing+=("${mode}:${agent}")
    done
  done
  [[ ${#missing[@]} -eq 0 ]] || fail "Agent references not found: ${missing[*]}"
}

@test "mode-overlay: conditional agent references exist" {
  local missing=()
  for mode in "${EXPECTED_MODES[@]}"; do
    local file="$MODES_DIR/${mode}.md"
    local agents; agents=$(sed -n '/conditional:/,/^[^[:space:]]/p' "$file" 2>/dev/null | grep -oE 'fg-[0-9]+-[a-z-]+' || true)
    for agent in $agents; do
      [[ -f "$AGENTS_DIR/${agent}.md" ]] || missing+=("${mode}:${agent}")
    done
  done
  [[ ${#missing[@]} -eq 0 ]] || fail "Conditional agent references not found: ${missing[*]}"
}

@test "mode-overlay: target_score references are valid" {
  for mode in "${EXPECTED_MODES[@]}"; do
    local file="$MODES_DIR/${mode}.md"
    local targets; targets=$(grep -E 'target_score:' "$file" 2>/dev/null | sed 's/.*target_score:[[:space:]]*//' || true)
    while IFS= read -r target; do
      [[ -z "$target" ]] && continue
      if [[ "$target" =~ ^[0-9]+$ ]] || [[ "$target" == "pass_threshold" ]] || [[ "$target" == "target_score" ]]; then
        continue
      else
        fail "${mode}.md has invalid target_score value: $target"
      fi
    done <<< "$targets"
  done
}

@test "mode-overlay: bugfix mode reduces review batch" {
  local file="$MODES_DIR/bugfix.md"
  local batch_line; batch_line=$(grep "batch_1:" "$file" || true)
  [[ -n "$batch_line" ]] || fail "bugfix.md missing batch_1 definition"
  local agent_count; agent_count=$(echo "$batch_line" | grep -oE 'fg-[0-9]+-[a-z-]+' | wc -l | tr -d ' ')
  [[ $agent_count -le 3 ]] || fail "bugfix.md batch_1 has $agent_count agents, expected <= 3"
}

@test "mode-overlay: bootstrap mode skips Stage 4" {
  local file="$MODES_DIR/bootstrap.md"
  grep -q "skip: true\|skip:true" "$file" || fail "bootstrap.md does not document Stage 4 skip"
  grep -q "implement" "$file" || fail "bootstrap.md does not reference implement stage"
}

@test "mode-overlay: standard mode has no stage overrides" {
  local file="$MODES_DIR/standard.md"
  grep -q "stages: {}" "$file" || fail "standard.md should have empty stages"
}

@test "mode-overlay: all modes have stages section in frontmatter" {
  for mode in "${EXPECTED_MODES[@]}"; do
    local file="$MODES_DIR/${mode}.md"
    local frontmatter; frontmatter=$(sed -n '2,/^---$/p' "$file")
    echo "$frontmatter" | grep -q "stages:" || fail "${mode}.md frontmatter missing stages: section"
  done
}
