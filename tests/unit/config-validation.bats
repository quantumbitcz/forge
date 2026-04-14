#!/usr/bin/env bash

setup() {
  load '../helpers/test-helpers'
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

@test "validate-config: accepts platform.windows_mode: auto" {
  local config_file="${BATS_TEST_TMPDIR}/platform-auto.md"
  cat > "$config_file" << 'EOF'
```yaml
components:
  language: kotlin
  framework: spring
  testing: kotest
platform:
  windows_mode: auto
```
EOF
  run bash "$PLUGIN_ROOT/shared/validate-config.sh" "$config_file"
  assert_success
}

@test "validate-config: accepts platform.windows_mode: wsl" {
  local config_file="${BATS_TEST_TMPDIR}/platform-wsl.md"
  cat > "$config_file" << 'EOF'
```yaml
components:
  language: kotlin
  framework: spring
  testing: kotest
platform:
  windows_mode: wsl
```
EOF
  run bash "$PLUGIN_ROOT/shared/validate-config.sh" "$config_file"
  assert_success
}

@test "validate-config: accepts platform.windows_mode: gitbash" {
  local config_file="${BATS_TEST_TMPDIR}/platform-gitbash.md"
  cat > "$config_file" << 'EOF'
```yaml
components:
  language: kotlin
  framework: spring
  testing: kotest
platform:
  windows_mode: gitbash
```
EOF
  run bash "$PLUGIN_ROOT/shared/validate-config.sh" "$config_file"
  assert_success
}

@test "validate-config: warns on invalid platform.windows_mode" {
  local config_file="${BATS_TEST_TMPDIR}/platform-invalid.md"
  cat > "$config_file" << 'EOF'
```yaml
components:
  language: kotlin
  framework: spring
  testing: kotest
platform:
  windows_mode: native
```
EOF
  run bash "$PLUGIN_ROOT/shared/validate-config.sh" "$config_file"
  [[ "$status" -eq 2 ]]
  assert_output --partial "platform.windows_mode"
}
