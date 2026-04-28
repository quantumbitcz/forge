#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

# Thin launcher skills that dispatch agents
THIN_LAUNCHERS=(forge-run forge-fix forge-shape forge-sprint forge-bootstrap forge-migration)

@test "skill-agent-refs: thin launchers reference valid agents" {
  for s in "${THIN_LAUNCHERS[@]}"; do
    local skill="$SKILLS_DIR/$s/SKILL.md"
    local refs
    refs=$(grep -oE 'fg-[0-9]{3}-[a-z-]+' "$skill" 2>/dev/null | sort -u)
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      [ -f "$AGENTS_DIR/${ref}.md" ] || fail "Skill $s references ${ref} but agent file missing"
    done <<< "$refs"
  done
}

@test "skill-agent-refs: forge-run references orchestrator" {
  run grep -q 'fg-100-orchestrator\|orchestrator' "$SKILLS_DIR/forge run/SKILL.md"
  assert_success
}

@test "skill-agent-refs: forge-fix references orchestrator" {
  run grep -q 'fg-100-orchestrator\|orchestrator' "$SKILLS_DIR/forge fix/SKILL.md"
  assert_success
}

@test "skill-agent-refs: forge-shape references shaper" {
  run grep -q 'fg-010-shaper\|shaper' "$SKILLS_DIR/forge run/SKILL.md"
  assert_success
}

@test "skill-agent-refs: forge-sprint references sprint orchestrator" {
  run grep -q 'fg-090-sprint-orchestrator\|sprint' "$SKILLS_DIR/forge sprint/SKILL.md"
  assert_success
}

@test "skill-agent-refs: no skill references deleted fg-420" {
  for dir in "$SKILLS_DIR"/*/; do
    run grep -q 'fg-420' "${dir}SKILL.md"
    assert_failure  # Should NOT find fg-420
  done
}
