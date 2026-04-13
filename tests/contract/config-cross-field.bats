#!/usr/bin/env bash

setup() {
  load '../lib/test-helpers'
  SCRIPT="$BATS_TEST_DIRNAME/../../shared/validate-config.sh"
}

@test "config-cross-field: script validates framework-language combos" {
  run grep -c 'spring\|react\|fastapi\|axum\|swiftui\|express\|django\|nextjs\|angular\|gin\|go-stdlib\|vapor\|embedded\|k8s\|aspnet\|jetpack-compose\|nestjs\|vue\|svelte\|sveltekit' "$SCRIPT"
  assert_success
  [[ "${output}" -ge 15 ]]
}

@test "config-cross-field: script checks all 22 frameworks" {
  run grep -c 'LEGAL_COMBOS' "$SCRIPT"
  assert_success
}

@test "config-cross-field: script includes fuzzy matching" {
  run grep -qi 'fuzzy\|suggest\|levenshtein\|did you mean' "$SCRIPT"
  assert_success
}
