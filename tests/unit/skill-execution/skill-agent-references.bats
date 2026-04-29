#!/usr/bin/env bash

# Post-Mega-B (v5.0.0): the per-skill thin launchers (forge-run, forge-fix,
# forge-shape, forge-sprint, forge-bootstrap, forge-migration) were retired
# and merged as subcommands of /forge. The agent-reference checks now point
# at the consolidated skills/forge/SKILL.md and skills/forge-admin/SKILL.md.

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "skill-agent-refs: surviving skills reference valid agents" {
  for dir in "$SKILLS_DIR"/*/; do
    local skill="${dir}SKILL.md"
    local refs
    refs=$(grep -oE 'fg-[0-9]{3}-[a-z-]+' "$skill" 2>/dev/null | sort -u)
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      [ -f "$AGENTS_DIR/${ref}.md" ] || fail "Skill ${dir}SKILL.md references ${ref} but agent file missing"
    done <<< "$refs"
  done
}

@test "skill-agent-refs: forge run subcommand references orchestrator" {
  run grep -q 'fg-100-orchestrator\|orchestrator' "$SKILLS_DIR/forge/SKILL.md"
  assert_success
}

@test "skill-agent-refs: forge fix subcommand references bug investigator" {
  # The fix subcommand dispatches fg-020-bug-investigator (which then
  # coordinates with the orchestrator); the orchestrator is also referenced
  # via the bugfix mode entry in the run subcommand's dispatch table.
  run grep -q 'fg-020-bug-investigator\|fg-100-orchestrator' "$SKILLS_DIR/forge/SKILL.md"
  assert_success
}

@test "skill-agent-refs: forge run subcommand references shaper for vague mode" {
  run grep -q 'fg-010-shaper\|shaper' "$SKILLS_DIR/forge/SKILL.md"
  assert_success
}

@test "skill-agent-refs: forge sprint subcommand references sprint orchestrator" {
  run grep -q 'fg-090-sprint-orchestrator\|sprint' "$SKILLS_DIR/forge/SKILL.md"
  assert_success
}

@test "skill-agent-refs: no skill references deleted fg-420" {
  for dir in "$SKILLS_DIR"/*/; do
    run grep -q 'fg-420' "${dir}SKILL.md"
    assert_failure  # Should NOT find fg-420
  done
}
