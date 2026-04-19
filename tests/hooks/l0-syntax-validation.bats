#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  load './helpers/mock-tool-input'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/pre_tool_use.py"
}

@test "l0-syntax: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "l0-syntax: has python3 shebang" {
  run head -1 "$HOOK_SCRIPT"
  assert_output --partial "python3"
}

@test "l0-syntax: exits 0 when FORGE_L0_ENABLED is false" {
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"/tmp/test.ts\"}}' | FORGE_L0_ENABLED=false python3 '$HOOK_SCRIPT'"
  assert_success
}

@test "l0-syntax: handles empty stdin gracefully" {
  run bash -c "echo '' | python3 '$HOOK_SCRIPT'"
  assert_success  # graceful degradation
}

# ---------------------------------------------------------------------------
# Behavioral tests (SPEC-05): 12 new tests verifying runtime behavior
# ---------------------------------------------------------------------------

@test "l0-syntax: blocks Edit that introduces syntax error (mocked tree-sitter)" {
  # Mock tree-sitter to return an ERROR node
  mock_command "tree-sitter" 'echo "(program (ERROR [1, 0] - [1, 5]))"; exit 0'

  # Mock python3: handle both inline -c JSON parse and apply-edit-preview.py
  local real_python
  real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [[ -z "$real_python" ]]; then
    skip "python3 not available"
  fi
  # Create a mock that delegates to real python but fakes the preview output
  cat > "${MOCK_BIN}/python3" <<PYEOF
#!/usr/bin/env bash
# If called with apply-edit-preview.py, create a dummy file at --output
if echo "\$*" | grep -q 'apply-edit-preview'; then
  # Find the --output arg
  while [[ \$# -gt 0 ]]; do
    case "\$1" in
      --output) echo "function foo() { return 1" > "\$2"; exit 0 ;;
      *) shift ;;
    esac
  done
  exit 0
fi
# Otherwise delegate to real python for JSON parsing
exec "$real_python" "\$@"
PYEOF
  chmod +x "${MOCK_BIN}/python3"

  export FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Edit
  export TOOL_INPUT
  TOOL_INPUT=$(make_edit_input "/tmp/test.ts" "return 1;" "return 1")

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_failure
  assert_output --partial "SYNTAX ERROR"
}

@test "l0-syntax: allows Edit that produces valid TypeScript (mocked tree-sitter)" {
  # Mock tree-sitter to return clean parse (no ERROR)
  mock_command "tree-sitter" 'echo "(program (function_declaration))"; exit 0'

  local real_python
  real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [[ -z "$real_python" ]]; then
    skip "python3 not available"
  fi
  cat > "${MOCK_BIN}/python3" <<PYEOF
#!/usr/bin/env bash
if echo "\$*" | grep -q 'apply-edit-preview'; then
  while [[ \$# -gt 0 ]]; do
    case "\$1" in
      --output) echo "function foo() { return 1; }" > "\$2"; exit 0 ;;
      *) shift ;;
    esac
  done
  exit 0
fi
exec "$real_python" "\$@"
PYEOF
  chmod +x "${MOCK_BIN}/python3"

  export FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Edit
  export TOOL_INPUT
  TOOL_INPUT=$(make_edit_input "/tmp/test.ts" "old" "new")

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "l0-syntax: blocks Write that creates invalid Python (mocked tree-sitter)" {
  mock_command "tree-sitter" 'echo "(module (ERROR [1, 0] - [1, 10]))"; exit 0'

  local real_python
  real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [[ -z "$real_python" ]]; then
    skip "python3 not available"
  fi
  cat > "${MOCK_BIN}/python3" <<PYEOF
#!/usr/bin/env bash
if echo "\$*" | grep -q 'apply-edit-preview'; then
  while [[ \$# -gt 0 ]]; do
    case "\$1" in
      --output) echo "def foo(:" > "\$2"; exit 0 ;;
      *) shift ;;
    esac
  done
  exit 0
fi
exec "$real_python" "\$@"
PYEOF
  chmod +x "${MOCK_BIN}/python3"

  export FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Write
  export TOOL_INPUT
  TOOL_INPUT=$(make_write_input "/tmp/test.py" "def foo(:")

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_failure
  assert_output --partial "SYNTAX ERROR"
}

@test "l0-syntax: allows Write that creates valid Python (mocked tree-sitter)" {
  mock_command "tree-sitter" 'echo "(module (function_definition))"; exit 0'

  local real_python
  real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [[ -z "$real_python" ]]; then
    skip "python3 not available"
  fi
  cat > "${MOCK_BIN}/python3" <<PYEOF
#!/usr/bin/env bash
if echo "\$*" | grep -q 'apply-edit-preview'; then
  while [[ \$# -gt 0 ]]; do
    case "\$1" in
      --output) echo "def foo(): pass" > "\$2"; exit 0 ;;
      *) shift ;;
    esac
  done
  exit 0
fi
exec "$real_python" "\$@"
PYEOF
  chmod +x "${MOCK_BIN}/python3"

  export FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Write
  export TOOL_INPUT
  TOOL_INPUT=$(make_write_input "/tmp/test.py" "def foo(): pass")

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "l0-syntax: skips unsupported file extensions (.md, .json, .yaml)" {
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Edit

  for ext in md json yaml; do
    export TOOL_INPUT
    TOOL_INPUT=$(make_edit_input "/tmp/test.${ext}" "old" "new")
    run python3 "$HOOK_SCRIPT" </dev/null
    assert_success
  done
}

@test "l0-syntax: skips when tree-sitter not installed" {
  # Ensure tree-sitter is NOT in PATH by using only MOCK_BIN (which is empty)
  export PATH="${MOCK_BIN}"
  # Need python3 for JSON parsing
  local real_python
  real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [[ -n "$real_python" ]]; then
    cp "$real_python" "${MOCK_BIN}/python3" 2>/dev/null || ln -sf "$real_python" "${MOCK_BIN}/python3"
    chmod +x "${MOCK_BIN}/python3"
  fi

  export FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Edit
  export TOOL_INPUT
  TOOL_INPUT=$(make_edit_input "/tmp/test.ts" "old" "new")

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success

  # Verify log entry was written
  if [[ -f "$FORGE_DIR/.hook-failures.log" ]]; then
    run grep -q 'tree-sitter_not_installed' "$FORGE_DIR/.hook-failures.log"
    assert_success
  fi
}

@test "l0-syntax: respects FORGE_L0_LANGUAGES filter" {
  export FORGE_L0_ENABLED=true
  export FORGE_L0_LANGUAGES="typescript python"
  export TOOL_NAME=Edit
  export TOOL_INPUT
  # .go is not in the allowed list — should be skipped
  TOOL_INPUT=$(make_edit_input "/tmp/test.go" "old" "new")

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "l0-syntax: handles malformed TOOL_INPUT gracefully" {
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Edit
  export TOOL_INPUT="not valid json at all"

  export FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "l0-syntax: handles empty file_path gracefully" {
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Edit
  export TOOL_INPUT='{"file_path":""}'

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "l0-syntax: handles missing python gracefully" {
  # PATH with only a mock tree-sitter but no python3/python
  export PATH="${MOCK_BIN}"
  mock_command "tree-sitter" 'echo "(program)"; exit 0'
  # Explicitly do NOT create python3 or python in MOCK_BIN

  export FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Edit
  export TOOL_INPUT='{"file_path":"/tmp/test.ts","old_string":"a","new_string":"b"}'

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "l0-syntax: increments .l0-total-checks counter on valid run" {
  mock_command "tree-sitter" 'echo "(program (function_declaration))"; exit 0'

  local real_python
  real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [[ -z "$real_python" ]]; then
    skip "python3 not available"
  fi
  cat > "${MOCK_BIN}/python3" <<PYEOF
#!/usr/bin/env bash
if echo "\$*" | grep -q 'apply-edit-preview'; then
  while [[ \$# -gt 0 ]]; do
    case "\$1" in
      --output) echo "function foo() {}" > "\$2"; exit 0 ;;
      *) shift ;;
    esac
  done
  exit 0
fi
exec "$real_python" "\$@"
PYEOF
  chmod +x "${MOCK_BIN}/python3"

  export FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
  export FORGE_L0_ENABLED=true
  export TOOL_NAME=Edit
  export TOOL_INPUT
  TOOL_INPUT=$(make_edit_input "/tmp/test.ts" "old" "new")

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success

  # Verify counter was incremented
  assert [ -f "$FORGE_DIR/.l0-total-checks" ]
  local count
  count=$(cat "$FORGE_DIR/.l0-total-checks")
  assert [ "$count" -ge 1 ]
}

@test "l0-syntax: maps tsx/jsx to typescript/javascript for language filter" {
  mock_command "tree-sitter" 'echo "(program (jsx_element))"; exit 0'

  local real_python
  real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  if [[ -z "$real_python" ]]; then
    skip "python3 not available"
  fi
  cat > "${MOCK_BIN}/python3" <<PYEOF
#!/usr/bin/env bash
if echo "\$*" | grep -q 'apply-edit-preview'; then
  while [[ \$# -gt 0 ]]; do
    case "\$1" in
      --output) echo "const x = <div/>;" > "\$2"; exit 0 ;;
      *) shift ;;
    esac
  done
  exit 0
fi
exec "$real_python" "\$@"
PYEOF
  chmod +x "${MOCK_BIN}/python3"

  export FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
  export FORGE_L0_ENABLED=true
  export FORGE_L0_LANGUAGES="typescript"
  export TOOL_NAME=Edit
  export TOOL_INPUT
  # .tsx maps to typescript — should NOT be filtered out
  TOOL_INPUT=$(make_edit_input "/tmp/component.tsx" "old" "new")

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success

  # Verify it actually ran (counter incremented) rather than being skipped
  assert [ -f "$FORGE_DIR/.l0-total-checks" ]
  local count
  count=$(cat "$FORGE_DIR/.l0-total-checks")
  assert [ "$count" -ge 1 ]
}
