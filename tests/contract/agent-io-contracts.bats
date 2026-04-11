#!/usr/bin/env bats
# Contract tests: agent I/O contracts — verifies that agent documentation
# describes required input/output fields per dispatch contracts.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

# ===========================================================================
# 1. fg-400 quality gate documents "score" in output
# ===========================================================================
@test "agent-io: fg-400 quality gate documents score in output" {
  local agent="$AGENTS_DIR/fg-400-quality-gate.md"
  [[ -f "$agent" ]] || fail "fg-400-quality-gate.md not found"
  grep -qi "score" "$agent" \
    || fail "fg-400 quality gate does not document 'score' in output"
}

# ===========================================================================
# 2. fg-500 test gate documents "tests_pass" and "analysis_pass"
# ===========================================================================
@test "agent-io: fg-500 test gate documents tests_pass" {
  local agent="$AGENTS_DIR/fg-500-test-gate.md"
  [[ -f "$agent" ]] || fail "fg-500-test-gate.md not found"
  grep -qi "tests_pass\|tests.pass\|test.*pass" "$agent" \
    || fail "fg-500 test gate does not document 'tests_pass'"
}

@test "agent-io: fg-500 test gate documents analysis_pass" {
  local agent="$AGENTS_DIR/fg-500-test-gate.md"
  [[ -f "$agent" ]] || fail "fg-500-test-gate.md not found"
  grep -qi "analysis_pass\|analysis.pass" "$agent" \
    || fail "fg-500 test gate does not document 'analysis_pass'"
}

# ===========================================================================
# 3. fg-300 implementer documents "task" in input
# ===========================================================================
@test "agent-io: fg-300 implementer documents task in input" {
  local agent="$AGENTS_DIR/fg-300-implementer.md"
  [[ -f "$agent" ]] || fail "fg-300-implementer.md not found"
  grep -qi "task" "$agent" \
    || fail "fg-300 implementer does not document 'task' in input"
}

# ===========================================================================
# 4. fg-200 planner documents "plan" in output
# ===========================================================================
@test "agent-io: fg-200 planner documents plan in output" {
  local agent="$AGENTS_DIR/fg-200-planner.md"
  [[ -f "$agent" ]] || fail "fg-200-planner.md not found"
  grep -qi "plan" "$agent" \
    || fail "fg-200 planner does not document 'plan' in output"
}

# ===========================================================================
# 5. fg-210 validator documents verdict (GO/REVISE/NO-GO) in output
# ===========================================================================
@test "agent-io: fg-210 validator documents verdict GO/REVISE/NO-GO" {
  local agent="$AGENTS_DIR/fg-210-validator.md"
  [[ -f "$agent" ]] || fail "fg-210-validator.md not found"
  grep -qi "GO\|REVISE\|NO.GO" "$agent" \
    || fail "fg-210 validator does not document verdict (GO/REVISE/NO-GO)"
}

# ===========================================================================
# 6. fg-600 PR builder documents "pr_url" in output
# ===========================================================================
@test "agent-io: fg-600 PR builder documents pr_url in output" {
  local agent="$AGENTS_DIR/fg-600-pr-builder.md"
  [[ -f "$agent" ]] || fail "fg-600-pr-builder.md not found"
  grep -qi "pr_url\|pr.url" "$agent" \
    || fail "fg-600 PR builder does not document 'pr_url' in output"
}

# ===========================================================================
# 7. fg-590 pre-ship verifier documents verdict (SHIP/BLOCK)
# ===========================================================================
@test "agent-io: fg-590 pre-ship verifier documents verdict SHIP/BLOCK" {
  local agent="$AGENTS_DIR/fg-590-pre-ship-verifier.md"
  [[ -f "$agent" ]] || fail "fg-590-pre-ship-verifier.md not found"
  grep -qi "SHIP\|BLOCK" "$agent" \
    || fail "fg-590 pre-ship verifier does not document verdict (SHIP/BLOCK)"
}

# ===========================================================================
# 8. fg-100 orchestrator documents "stage notes" for inter-stage communication
# ===========================================================================
@test "agent-io: fg-100 orchestrator documents stage notes" {
  local agent="$AGENTS_DIR/fg-100-orchestrator.md"
  [[ -f "$agent" ]] || fail "fg-100-orchestrator.md not found"
  grep -qi "stage.notes\|stage notes" "$agent" \
    || fail "fg-100 orchestrator does not document 'stage_notes' in output"
}

# ===========================================================================
# 9. fg-010 shaper documents "acceptance criteria" in output
# ===========================================================================
@test "agent-io: fg-010 shaper documents acceptance_criteria in output" {
  local agent="$AGENTS_DIR/fg-010-shaper.md"
  [[ -f "$agent" ]] || fail "fg-010-shaper.md not found"
  grep -qi "acceptance.criteria\|acceptance criteria" "$agent" \
    || fail "fg-010 shaper does not document 'acceptance_criteria' in output"
}

# ===========================================================================
# 10. fg-700 retrospective documents "learnings" in output
# ===========================================================================
@test "agent-io: fg-700 retrospective documents learnings in output" {
  local agent="$AGENTS_DIR/fg-700-retrospective.md"
  [[ -f "$agent" ]] || fail "fg-700-retrospective.md not found"
  grep -qi "learning" "$agent" \
    || fail "fg-700 retrospective does not document 'learnings' in output"
}
