#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
  SHARED_DIR="$BATS_TEST_DIRNAME/../../../shared"
}

@test "fg-100: dispatches only existing agents" {
  local agent="$AGENTS_DIR/fg-100-orchestrator.md"
  local refs
  refs=$(grep -oE 'fg-[0-9]{3}-[a-z-]+' "$agent" | sort -u)
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    [ -f "$AGENTS_DIR/${ref}.md" ] || fail "fg-100 references ${ref} but agent file missing"
  done <<< "$refs"
}

@test "fg-100: has Agent in tools list" {
  run grep -q 'Agent' "$AGENTS_DIR/fg-100-orchestrator.md"
  assert_success
}

@test "fg-100: documents all 10 pipeline stages" {
  local agent="$AGENTS_DIR/fg-100-orchestrator.md"
  for stage in PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING; do
    run grep -qi "$stage" "$agent"
    assert_success
  done
}

@test "fg-100: references state.json fields documented in schema" {
  local agent="$AGENTS_DIR/fg-100-orchestrator.md"
  for field in story_state total_retries mode score; do
    run grep -q "$field" "$agent"
    assert_success
  done
}

@test "fg-100: frontmatter name matches filename" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-100-orchestrator.md"
  assert_output "fg-100-orchestrator"
}
