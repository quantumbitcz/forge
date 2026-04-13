#!/usr/bin/env bash

setup() {
  load '../lib/test-helpers'
  SCRIPT="$BATS_TEST_DIRNAME/../../shared/validate-config.sh"
  FIXTURES="$BATS_TEST_DIRNAME/../fixtures/config"
}

@test "config-validation: script exists and is executable" {
  assert [ -x "$SCRIPT" ]
}

@test "config-validation: valid spring-kotlin config passes" {
  run "$SCRIPT" "$FIXTURES/valid-spring-kotlin.md"
  assert_success
  assert_output --partial "PASS"
}

@test "config-validation: invalid spring-python combo fails" {
  run "$SCRIPT" "$FIXTURES/invalid-spring-python.md"
  assert_failure
  assert_output --partial "ERROR"
  assert_output --partial "spring"
  assert_output --partial "python"
}

@test "config-validation: typo framework suggests correction" {
  run "$SCRIPT" "$FIXTURES/typo-framework.md"
  assert_failure
  assert_output --partial "react"
}

@test "config-validation: missing file exits with error" {
  run "$SCRIPT" "/nonexistent/path.md"
  assert_failure
  assert_output --partial "ERROR"
}

@test "config-validation: empty file without yaml block fails" {
  local tmpfile="${BATS_TEST_TMPDIR}/empty.md"
  echo "# No yaml here" > "$tmpfile"
  run "$SCRIPT" "$tmpfile"
  assert_failure
  assert_output --partial "ERROR"
}
