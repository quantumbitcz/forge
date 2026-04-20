#!/usr/bin/env bats

@test "spec documents bugfix + bootstrap as skip_in_modes default" {
  grep -q "skip_in_modes: \[bugfix, bootstrap\]" \
    "$BATS_TEST_DIRNAME/../../modules/frameworks/spring/forge-config-template.md"
}

@test "speculation.md forbids speculation in bugfix/bootstrap" {
  grep -q "bugfix.bootstrap modes" "$BATS_TEST_DIRNAME/../../shared/speculation.md" \
    || grep -q "bugfix/bootstrap" "$BATS_TEST_DIRNAME/../../shared/speculation.md"
}
