#!/usr/bin/env bats
# Structural test: verify markdown cross-references point to existing files

load '../helpers/test-helpers'

@test "all markdown cross-references point to existing files" {
  local violations=0

  while IFS= read -r -d '' md; do
    # Extract path-qualified .md references (per REVISIONS SPEC-09 #3)
    local refs
    refs=$(grep -oE '[a-zA-Z0-9_./-]+\.md' "$md" 2>/dev/null | sort -u || true)

    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      # Skip if inside a code block (heuristic: skip if ref contains ://)
      [[ "$ref" == *"://"* ]] && continue
      # Search for the referenced file
      local found
      found=$(find "$PLUGIN_ROOT" -name "$(basename "$ref")" -not -path '*/.git/*' 2>/dev/null | head -1)
      if [[ -z "$found" ]]; then
        echo "BROKEN REF: $md references $ref but file not found"
        violations=$((violations + 1))
      fi
    done <<< "$refs"
  done < <(find "$PLUGIN_ROOT/shared" "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/skills" -name "*.md" -print0 2>/dev/null)

  [[ "$violations" -eq 0 ]]
}

@test "all agent references in orchestrator point to existing agents" {
  local violations=0
  local orch="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
  [[ -f "$orch" ]] || skip "orchestrator not found"

  local agent_refs
  agent_refs=$(grep -oE 'fg-[0-9]+-[a-z-]+' "$orch" | sort -u)

  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    if [[ ! -f "$PLUGIN_ROOT/agents/${ref}.md" ]]; then
      echo "BROKEN: orchestrator references $ref but agents/${ref}.md not found"
      violations=$((violations + 1))
    fi
  done <<< "$agent_refs"

  [[ "$violations" -eq 0 ]]
}

@test "all skill references in agents point to existing skills" {
  local violations=0
  local skills_dir="$PLUGIN_ROOT/skills"

  while IFS= read -r -d '' agent; do
    # Extract /skill-name references (backtick-escaped, lowercase with hyphens)
    local refs
    refs=$(grep -oE '`/[a-z][-a-z]+`' "$agent" 2>/dev/null | sed 's/`//g; s|^/||' | sort -u || true)

    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      if [[ ! -d "$skills_dir/$ref" ]]; then
        echo "BROKEN: $(basename "$agent") references /$ref but skills/$ref/ not found"
        violations=$((violations + 1))
      fi
    done <<< "$refs"
  done < <(find "$PLUGIN_ROOT/agents" -name "*.md" -print0 2>/dev/null)

  [[ "$violations" -eq 0 ]]
}

@test "cross-references: convergence-engine.md has See Also section" {
  grep -q "## See Also" "$PLUGIN_ROOT/shared/convergence-engine.md"
}

@test "cross-references: scoring.md has See Also section" {
  grep -q "## See Also" "$PLUGIN_ROOT/shared/scoring.md"
}

@test "cross-references: agent-philosophy.md has See Also section" {
  grep -q "## See Also" "$PLUGIN_ROOT/shared/agent-philosophy.md"
}

@test "cross-references: convergence-engine.md references stage-contract.md" {
  grep -q "stage-contract.md" "$PLUGIN_ROOT/shared/convergence-engine.md"
}

@test "cross-references: scoring.md references convergence-engine.md" {
  grep -q "convergence-engine.md" "$PLUGIN_ROOT/shared/scoring.md"
}
