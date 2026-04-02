#!/usr/bin/env bats
# Structural tests: documentation subsystem file presence and format.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"
SKILLS_DIR="$PLUGIN_ROOT/skills"
MODULES_DIR="$PLUGIN_ROOT/modules"

@test "docs-structural: fg-130-docs-discoverer.md exists with correct frontmatter" {
  local agent_file="$AGENTS_DIR/fg-130-docs-discoverer.md"
  [ -f "$agent_file" ] || fail "Agent file not found: $agent_file"
  local first_line
  first_line="$(head -1 "$agent_file")"
  [[ "$first_line" == "---" ]] || fail "Missing frontmatter opening ---"
  grep -q "^name: fg-130-docs-discoverer" "$agent_file" || fail "Missing or incorrect name field"
  grep -q "tools:" "$agent_file" || fail "Missing tools field"
}

@test "docs-structural: docs-consistency-reviewer.md exists with correct frontmatter" {
  local agent_file="$AGENTS_DIR/docs-consistency-reviewer.md"
  [ -f "$agent_file" ] || fail "Agent file not found: $agent_file"
  local first_line
  first_line="$(head -1 "$agent_file")"
  [[ "$first_line" == "---" ]] || fail "Missing frontmatter opening ---"
  grep -q "^name: docs-consistency-reviewer" "$agent_file" || fail "Missing or incorrect name field"
  grep -q "tools:" "$agent_file" || fail "Missing tools field"
}

@test "docs-structural: fg-350-docs-generator.md exists with correct frontmatter" {
  local agent_file="$AGENTS_DIR/fg-350-docs-generator.md"
  [ -f "$agent_file" ] || fail "Agent file not found: $agent_file"
  local first_line
  first_line="$(head -1 "$agent_file")"
  [[ "$first_line" == "---" ]] || fail "Missing frontmatter opening ---"
  grep -q "^name: fg-350-docs-generator" "$agent_file" || fail "Missing or incorrect name field"
  grep -q "tools:" "$agent_file" || fail "Missing tools field"
}

@test "docs-structural: docs-generate skill exists" {
  [ -f "$SKILLS_DIR/docs-generate/SKILL.md" ] || fail "Skill file not found"
  grep -q "^name: docs-generate" "$SKILLS_DIR/docs-generate/SKILL.md" || fail "Missing or incorrect name field"
}

@test "docs-structural: modules/documentation/conventions.md exists" {
  [ -f "$MODULES_DIR/documentation/conventions.md" ] || fail "Generic documentation conventions not found"
}

@test "docs-structural: modules/documentation/templates/ contains required templates" {
  local required_templates=(readme.md architecture.md adr.md onboarding.md runbook.md changelog.md domain-model.md user-guide.md)
  local missing=()
  for tmpl in "${required_templates[@]}"; do
    [ -f "$MODULES_DIR/documentation/templates/$tmpl" ] || missing+=("$tmpl")
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing templates: ${missing[*]}"
  fi
}

@test "docs-structural: modules/documentation/diagram-patterns.md exists" {
  [ -f "$MODULES_DIR/documentation/diagram-patterns.md" ] || fail "Diagram patterns file not found"
}

@test "docs-structural: all framework doc bindings have conventions.md" {
  load '../lib/module-lists'
  local missing=()
  for fw in "${DISCOVERED_DOC_BINDINGS[@]}"; do
    [ -f "$MODULES_DIR/frameworks/$fw/documentation/conventions.md" ] || missing+=("$fw")
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Frameworks missing documentation/conventions.md: ${missing[*]}"
  fi
}

@test "docs-structural: documentation binding count guard" {
  load '../lib/module-lists'
  guard_min_count "documentation bindings" "${#DISCOVERED_DOC_BINDINGS[@]}" "$MIN_DOCUMENTATION_BINDINGS"
}

@test "docs-structural: shared/learnings/documentation.md exists" {
  [ -f "$PLUGIN_ROOT/shared/learnings/documentation.md" ] || fail "Documentation learnings file not found"
}
