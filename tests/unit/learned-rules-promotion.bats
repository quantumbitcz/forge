#!/usr/bin/env bash

setup() {
  load '../helpers/test-helpers'
  LEARNINGS_DIR="$BATS_TEST_DIRNAME/../../shared/learnings"
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../agents"
  SHARED_DIR="$BATS_TEST_DIRNAME/../../shared"
}

@test "learned-rules: rule-promotion.md exists" {
  assert [ -f "$LEARNINGS_DIR/rule-promotion.md" ]
}

@test "learned-rules: promotion threshold documented (>=3 occurrences, >=2 runs)" {
  run grep -i '>=.*3.*occurrences\|3.*occurrences\|occurrences.*3' "$LEARNINGS_DIR/rule-promotion.md"
  assert_success
}

@test "learned-rules: candidate schema documented" {
  for field in pattern severity category language occurrences status; do
    run grep -q "$field" "$LEARNINGS_DIR/rule-promotion.md"
    assert_success
  done
}

@test "learned-rules: decay rules documented (5 inactive runs)" {
  run grep -i '5.*inactive\|inactive.*5\|inactive_runs.*5' "$LEARNINGS_DIR/rule-promotion.md"
  assert_success
}

@test "learned-rules: 4 status values documented" {
  for status in candidate ready_for_promotion promoted demoted; do
    run grep -q "$status" "$LEARNINGS_DIR/rule-promotion.md"
    assert_success
  done
}

@test "learned-rules: retrospective references rule extraction" {
  run grep -i 'learned-candidates\|rule.*candidate\|Learning Extraction' "$AGENTS_DIR/fg-700-retrospective.md"
  assert_success
}

@test "learned-rules: orchestrator references rule promotion at PREFLIGHT" {
  run grep -i 'Rule Promotion\|learned-candidates\|learned-rules-override' "$AGENTS_DIR/fg-100-orchestrator.md"
  assert_success
}

@test "learned-rules: engine.sh loads learned-rules-override" {
  run grep -q 'learned-rules-override\|learned_rules\|LEARNED_RULES' "$SHARED_DIR/checks/engine.sh"
  assert_success
}

@test "learned-rules: engine.py loads learned-rules-override" {
  run grep -qi 'learned.rules.override\|learned_rules\|LEARNED_RULES' "$SHARED_DIR/checks/engine.py"
  assert_success
}
