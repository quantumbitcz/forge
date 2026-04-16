#!/usr/bin/env bats
# Contract tests: self-improving playbooks system.

load '../helpers/test-helpers'

SCHEMA="$PLUGIN_ROOT/shared/schemas/playbook-refinement-schema.json"
PLAYBOOKS_DOC="$PLUGIN_ROOT/shared/playbooks.md"
RETROSPECTIVE="$PLUGIN_ROOT/agents/fg-700-retrospective.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
SKILL="$PLUGIN_ROOT/skills/forge-playbook-refine/SKILL.md"
PREFLIGHT="$PLUGIN_ROOT/shared/preflight-constraints.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# 1. Schema exists and is valid JSON
# ---------------------------------------------------------------------------
@test "playbook-refinement: schema file exists" {
  [[ -f "$SCHEMA" ]]
}

@test "playbook-refinement: schema is valid JSON" {
  python3 -c "import json; json.load(open('$SCHEMA'))" 2>/dev/null \
    || fail "Schema is not valid JSON"
}

# ---------------------------------------------------------------------------
# 2. Schema defines required fields
# ---------------------------------------------------------------------------
@test "playbook-refinement: schema requires playbook_id" {
  grep -q '"playbook_id"' "$SCHEMA" \
    || fail "Schema missing playbook_id field"
}

@test "playbook-refinement: schema defines 4 refinement types" {
  grep -q '"scoring_gap"' "$SCHEMA" || fail "Missing scoring_gap type"
  grep -q '"stage_focus"' "$SCHEMA" || fail "Missing stage_focus type"
  grep -q '"acceptance_gap"' "$SCHEMA" || fail "Missing acceptance_gap type"
  grep -q '"parameter_default"' "$SCHEMA" || fail "Missing parameter_default type"
}

@test "playbook-refinement: schema defines proposal status values" {
  grep -q '"ready"' "$SCHEMA" || fail "Missing ready status"
  grep -q '"applied"' "$SCHEMA" || fail "Missing applied status"
  grep -q '"rejected"' "$SCHEMA" || fail "Missing rejected status"
  grep -q '"rolled_back"' "$SCHEMA" || fail "Missing rolled_back status"
}

# ---------------------------------------------------------------------------
# 3. Skill exists with correct frontmatter
# ---------------------------------------------------------------------------
@test "playbook-refinement: skill file exists" {
  [[ -f "$SKILL" ]]
}

@test "playbook-refinement: skill has name in frontmatter" {
  grep -q "name: forge-playbook-refine" "$SKILL" \
    || fail "Skill missing name frontmatter"
}

@test "playbook-refinement: skill has AskUserQuestion in allowed-tools" {
  grep -q "AskUserQuestion" "$SKILL" \
    || fail "Skill missing AskUserQuestion in allowed-tools"
}

# ---------------------------------------------------------------------------
# 4. Integration: retrospective references refinement
# ---------------------------------------------------------------------------
@test "playbook-refinement: retrospective agent references playbook refinement" {
  grep -qi "playbook.*refine\|refinement" "$RETROSPECTIVE" \
    || fail "fg-700-retrospective.md does not reference playbook refinement"
}

# ---------------------------------------------------------------------------
# 5. Integration: playbooks.md includes self-improvement section
# ---------------------------------------------------------------------------
@test "playbook-refinement: playbooks.md includes Self-Improvement section" {
  grep -q "Self-Improvement" "$PLAYBOOKS_DOC" \
    || fail "shared/playbooks.md missing Self-Improvement section"
}

# ---------------------------------------------------------------------------
# 6. Integration: orchestrator references auto-refine
# ---------------------------------------------------------------------------
@test "playbook-refinement: orchestrator references auto-refine" {
  grep -qi "auto.refine\|auto_refine" "$ORCHESTRATOR" \
    || fail "fg-100-orchestrator.md does not reference auto-refine"
}

# ---------------------------------------------------------------------------
# 7. Integration: preflight-constraints includes playbook refinement config
# ---------------------------------------------------------------------------
@test "playbook-refinement: preflight-constraints includes refine config" {
  grep -q "auto_refine" "$PREFLIGHT" \
    || fail "preflight-constraints.md missing auto_refine validation"
}

# ---------------------------------------------------------------------------
# 8. Integration: state-schema documents playbook-refinements directory
# ---------------------------------------------------------------------------
@test "playbook-refinement: state-schema documents playbook-refinements" {
  grep -q "playbook-refinements" "$STATE_SCHEMA" \
    || fail "state-schema.md missing playbook-refinements directory"
}

# ---------------------------------------------------------------------------
# 9. Guard rails: no threshold lowering in retrospective
# ---------------------------------------------------------------------------
@test "playbook-refinement: retrospective forbids lowering thresholds" {
  grep -qi "never.*lower.*threshold\|never.*pass_threshold" "$RETROSPECTIVE" \
    || fail "Retrospective does not explicitly forbid lowering thresholds"
}
