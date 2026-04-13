#!/usr/bin/env bash

setup() {
  load '../helpers/test-helpers'
  COMPRESS_SKILL="$BATS_TEST_DIRNAME/../../skills/forge-compress/SKILL.md"
}

@test "caveman-roundtrip: forge-compress documents --restore flag" {
  run grep -q '\-\-restore' "$COMPRESS_SKILL"
  assert_success
}

@test "caveman-roundtrip: forge-compress documents --dry-run flag" {
  run grep -q '\-\-dry-run' "$COMPRESS_SKILL"
  assert_success
}

@test "caveman-roundtrip: forge-compress documents --level flag" {
  run grep -q '\-\-level' "$COMPRESS_SKILL"
  assert_success
}

@test "caveman-roundtrip: forge-compress documents --scope flag" {
  run grep -q '\-\-scope' "$COMPRESS_SKILL"
  assert_success
}

@test "caveman-roundtrip: forge-compress documents backup rule" {
  run grep -qi 'original\.md\|backup' "$COMPRESS_SKILL"
  assert_success
}
