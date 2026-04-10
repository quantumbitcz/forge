#!/usr/bin/env bats
# Unit tests: finding format validation — validates that shared/validate-finding.sh
# correctly accepts/rejects finding lines per output-format.md.

load '../helpers/test-helpers'

VALIDATOR="$PLUGIN_ROOT/shared/validate-finding.sh"

@test "validate-finding: valid 5-field finding accepted" {
  run bash "$VALIDATOR" "src/User.kt:42 | ARCH-BOUNDARY | WARNING | crosses module boundary | move to shared module"
  assert_success
}

@test "validate-finding: valid 6-field finding with confidence accepted" {
  run bash "$VALIDATOR" "src/User.kt:42 | ARCH-BOUNDARY | CRITICAL | crosses module boundary | move to shared module | confidence:HIGH"
  assert_success
}

@test "validate-finding: missing severity field rejected" {
  run bash "$VALIDATOR" "src/User.kt:42 | ARCH-BOUNDARY | some message | hint"
  assert_failure
}

@test "validate-finding: invalid severity rejected" {
  run bash "$VALIDATOR" "src/User.kt:42 | ARCH-BOUNDARY | WARN | some message | hint"
  assert_failure
}

@test "validate-finding: invalid category code rejected" {
  run bash "$VALIDATOR" "src/User.kt:42 | arch-boundary | WARNING | some message | hint"
  assert_failure
}

@test "validate-finding: file:line without colon rejected" {
  run bash "$VALIDATOR" "file_only | ARCH-BOUNDARY | WARNING | some message | hint"
  assert_failure
}

@test "validate-finding: non-numeric line rejected" {
  run bash "$VALIDATOR" "src/User.kt:abc | ARCH-BOUNDARY | WARNING | some message | hint"
  assert_failure
}

@test "validate-finding: empty message rejected" {
  run bash "$VALIDATOR" "src/User.kt:42 | ARCH-BOUNDARY | WARNING |  | hint"
  assert_failure
}

@test "validate-finding: SCOUT-* category accepted" {
  run bash "$VALIDATOR" "src/User.kt:42 | SCOUT-IMPORT-UNUSED | INFO | unused import detected | remove import"
  assert_success
}

@test "validate-finding: 7+ fields rejected" {
  run bash "$VALIDATOR" "src/User.kt:42 | ARCH-BOUNDARY | WARNING | msg | hint | confidence:HIGH | extra"
  assert_failure
}

@test "validate-finding: line 0 for file-level finding accepted" {
  run bash "$VALIDATOR" "src/User.kt:0 | QUAL-LENGTH | INFO | file too large | split into modules"
  assert_success
}

@test "validate-finding: empty fix_hint accepted" {
  run bash "$VALIDATOR" "src/User.kt:42 | ARCH-BOUNDARY | WARNING | crosses boundary | "
  assert_success
}

@test "validate-finding: question mark file with line 0 accepted" {
  run bash "$VALIDATOR" "?:0 | REVIEW-GAP | INFO | Agent timed out | Re-run review"
  assert_success
}

@test "validate-finding: invalid confidence value rejected" {
  run bash "$VALIDATOR" "src/User.kt:42 | ARCH-BOUNDARY | WARNING | msg | hint | confidence:MAYBE"
  assert_failure
}

@test "validate-finding: escaped pipe in message accepted" {
  run bash "$VALIDATOR" 'src/User.kt:42 | ARCH-BOUNDARY | WARNING | message with \| pipe | hint'
  assert_success
}
