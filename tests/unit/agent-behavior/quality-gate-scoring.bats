#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-400: dispatches only existing reviewer agents" {
  local agent="$AGENTS_DIR/fg-400-quality-gate.md"
  local refs
  refs=$(grep -oP 'fg-4[0-9]{2}-[\w-]+' "$agent" | sort -u)
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    assert [ -f "$AGENTS_DIR/${ref}.md" ] \
      "fg-400 dispatches ${ref} but agent file missing"
  done <<< "$refs"
}

@test "fg-400: documents scoring formula" {
  run grep -q 'CRITICAL.*WARNING.*INFO\|100.*20.*5.*2' "$AGENTS_DIR/fg-400-quality-gate.md"
  assert_success
}

@test "fg-400: documents verdict thresholds (PASS/CONCERNS/FAIL)" {
  local agent="$AGENTS_DIR/fg-400-quality-gate.md"
  run grep -qi 'PASS' "$agent"
  assert_success
  run grep -qi 'CONCERNS' "$agent"
  assert_success
  run grep -qi 'FAIL' "$agent"
  assert_success
}

@test "fg-400: has Agent in tools for reviewer dispatch" {
  run grep -q 'Agent' "$AGENTS_DIR/fg-400-quality-gate.md"
  assert_success
}

@test "fg-400: documents deduplication" {
  run grep -qi 'dedup\|duplicate' "$AGENTS_DIR/fg-400-quality-gate.md"
  assert_success
}

@test "fg-400: frontmatter name matches filename" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-400-quality-gate.md"
  assert_output "fg-400-quality-gate"
}
