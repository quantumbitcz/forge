#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-350: documents documentation types" {
  run grep -qi 'README\|ADR\|API\|changelog\|architecture' "$AGENTS_DIR/fg-350-docs-generator.md"
  assert_success
}

@test "fg-350: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-350-docs-generator.md"
  assert_output "fg-350-docs-generator"
}

@test "fg-130: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-130-docs-discoverer.md"
  assert_output "fg-130-docs-discoverer"
}

@test "fg-135: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-135-wiki-generator.md"
  assert_output "fg-135-wiki-generator"
}
