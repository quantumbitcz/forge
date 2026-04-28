#!/usr/bin/env bats
# Unit tests: platform.sh _apply_platform_config and FORGE_WINDOWS_MODE

load '../helpers/test-helpers'

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-platform.XXXXXX")"
  mkdir -p "${TEST_TEMP}/project/.claude"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "platform.sh: FORGE_WINDOWS_MODE defaults to auto" {
  export FORGE_PROJECT_ROOT="${TEST_TEMP}/project"
  export FORGE_OS="windows"
  source "$PLUGIN_ROOT/shared/platform.sh"
  [[ "$FORGE_WINDOWS_MODE" == "auto" ]]
}

@test "platform.sh: FORGE_WINDOWS_MODE reads wsl from config" {
  export FORGE_PROJECT_ROOT="${TEST_TEMP}/project"
  export FORGE_OS="windows"
  cat > "${TEST_TEMP}/project/.claude/forge-config.md" << 'EOF'
```yaml
platform:
  windows_mode: wsl
```
EOF
  source "$PLUGIN_ROOT/shared/platform.sh"
  [[ "$FORGE_WINDOWS_MODE" == "wsl" ]]
}

@test "platform.sh: FORGE_WINDOWS_MODE reads gitbash from config" {
  export FORGE_PROJECT_ROOT="${TEST_TEMP}/project"
  export FORGE_OS="windows"
  cat > "${TEST_TEMP}/project/.claude/forge-config.md" << 'EOF'
```yaml
platform:
  windows_mode: gitbash
```
EOF
  source "$PLUGIN_ROOT/shared/platform.sh"
  [[ "$FORGE_WINDOWS_MODE" == "gitbash" ]]
}

@test "platform.sh: FORGE_WINDOWS_MODE ignores config when not windows" {
  export FORGE_PROJECT_ROOT="${TEST_TEMP}/project"
  export FORGE_OS="darwin"
  cat > "${TEST_TEMP}/project/.claude/forge-config.md" << 'EOF'
```yaml
platform:
  windows_mode: gitbash
```
EOF
  source "$PLUGIN_ROOT/shared/platform.sh"
  [[ "$FORGE_WINDOWS_MODE" == "auto" ]]
}

@test "platform.sh: invalid windows_mode defaults to auto" {
  export FORGE_PROJECT_ROOT="${TEST_TEMP}/project"
  export FORGE_OS="windows"
  cat > "${TEST_TEMP}/project/.claude/forge-config.md" << 'EOF'
```yaml
platform:
  windows_mode: native
```
EOF
  source "$PLUGIN_ROOT/shared/platform.sh"
  [[ "$FORGE_WINDOWS_MODE" == "auto" ]]
}
