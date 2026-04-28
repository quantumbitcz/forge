#!/usr/bin/env bats
# AC-PLAN-001..004: structural assertions on the fg-200 planner contract.
#
# These tests verify that the planner agent (fg-200) declares the contract
# the validator (fg-210) enforces. They grep the agent prose directly —
# not synthetic plan fixtures — because the planner's normative duties
# are stated in its system prompt.
load '../helpers/test-helpers'

PLANNER="$PLUGIN_ROOT/agents/fg-200-planner.md"

@test "fg-200 declares TDD ordering contract (W1)" {
  run grep -E '### TDD ordering' "$PLANNER"
  assert_success
  run grep -E 'preceding task .* MUST be `Type: test`' "$PLANNER"
  assert_success
}

@test "fg-200 references implementer prompt template (W2)" {
  run grep -F 'shared/prompts/implementer-prompt.md' "$PLANNER"
  assert_success
}

@test "fg-200 references spec-reviewer prompt template (W3)" {
  run grep -F 'shared/prompts/spec-reviewer-prompt.md' "$PLANNER"
  assert_success
}

@test "fg-200 declares Risk field with low|medium|high values (W4)" {
  run grep -E 'Risk: low \| medium \| high|Risk: low\|medium\|high' "$PLANNER"
  assert_success
}

@test "fg-200 declares 30-word risk-justification rule for Risk: high (W5)" {
  run grep -E 'at least 30 words|≥30 words|>= ?30 words' "$PLANNER"
  assert_success
}

@test "fg-200 documents validator-coupled REVISE on contract violations" {
  run grep -E 'fg-210.* (REVISE|rejects)' "$PLANNER"
  assert_success
}
