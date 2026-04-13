#!/usr/bin/env bash

setup() {
  load '../helpers/test-helpers'
  SCHEMA="$BATS_TEST_DIRNAME/../../shared/config-schema.json"
}

@test "caveman-config: schema includes caveman section" {
  run grep -q '"caveman"' "$SCHEMA"
  assert_success
}

@test "caveman-config: schema validates default_mode enum" {
  run grep -A5 '"default_mode"' "$SCHEMA"
  assert_success
  assert_output --partial "lite"
  assert_output --partial "full"
  assert_output --partial "ultra"
}

@test "caveman-config: schema validates output_mode includes off" {
  run grep -A5 '"output_mode"' "$SCHEMA"
  assert_success
  assert_output --partial "off"
}
