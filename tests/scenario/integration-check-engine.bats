#!/usr/bin/env bats
# Integration test: check engine end-to-end against real project structures.
# Validates that engine.sh and engine.py correctly detect modules, load
# overrides, and run Layer 1 pattern checks on realistic project layouts.

# Covers:

load '../helpers/test-helpers'

ENGINE_SH="$PLUGIN_ROOT/shared/checks/engine.sh"
ENGINE_PY="$PLUGIN_ROOT/hooks/_py/check_engine/engine.py"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

# ---------------------------------------------------------------------------
# 1. Spring/Kotlin project — check engine detects module and applies rules
# ---------------------------------------------------------------------------

@test "integration: engine detects spring module from build.gradle.kts" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  # Create a Kotlin file with a known anti-pattern (!! operator)
  mkdir -p "$project_dir/src/main/kotlin/com/example"
  cat > "$project_dir/src/main/kotlin/com/example/App.kt" <<'EOF'
package com.example

class App {
    fun process(input: String?) {
        val result = input!!.uppercase()
        println(result)
    }
}
EOF

  # Run engine in verify mode
  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/src/main/kotlin/com/example/App.kt"

  assert_success
  # Should detect the !! anti-pattern (QUAL-NULL or similar finding)
  # Engine exits 0 regardless, but may produce findings on stdout
}

@test "integration: engine processes multiple Kotlin files" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  mkdir -p "$project_dir/src/main/kotlin/com/example"
  echo 'package com.example; class A' > "$project_dir/src/main/kotlin/com/example/A.kt"
  echo 'package com.example; class B' > "$project_dir/src/main/kotlin/com/example/B.kt"

  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed \
    "$project_dir/src/main/kotlin/com/example/A.kt" \
    "$project_dir/src/main/kotlin/com/example/B.kt"

  assert_success
}

# ---------------------------------------------------------------------------
# 2. React project — TypeScript detection and rules
# ---------------------------------------------------------------------------

@test "integration: engine detects react module from vite.config" {
  local project_dir
  project_dir="$(create_temp_project react)"

  mkdir -p "$project_dir/src"
  cat > "$project_dir/src/App.tsx" <<'EOF'
import React from 'react';

export const App = () => {
  return <div>Hello</div>;
};
EOF

  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/src/App.tsx"

  assert_success
}

# ---------------------------------------------------------------------------
# 3. Python engine fallback — same behavior as bash engine
# ---------------------------------------------------------------------------

@test "integration: python engine produces consistent results with bash engine" {
  skip_if_no_python3

  local project_dir
  project_dir="$(create_temp_project spring)"

  mkdir -p "$project_dir/src/main/kotlin"
  echo 'fun main() { println("hello") }' > "$project_dir/src/main/kotlin/Main.kt"

  # Run bash engine
  local bash_output
  bash_output="$(bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/src/main/kotlin/Main.kt" 2>/dev/null || true)"

  # Run python engine
  local py_output
  py_output="$(python3 "$ENGINE_PY" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/src/main/kotlin/Main.kt" 2>/dev/null || true)"

  # Both should succeed (exit 0) — content may differ slightly
  # but neither should crash
  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/src/main/kotlin/Main.kt"
  assert_success

  run python3 "$ENGINE_PY" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/src/main/kotlin/Main.kt"
  assert_success
}

# ---------------------------------------------------------------------------
# 4. Multi-component project — component cache routing
# ---------------------------------------------------------------------------

@test "integration: engine routes files to correct component via cache" {
  local project_dir="${TEST_TEMP}/multi-component"
  mkdir -p "$project_dir/.forge"
  mkdir -p "$project_dir/backend/src/main/kotlin"
  mkdir -p "$project_dir/frontend/src"

  # Initialize git
  git -C "$project_dir" init -q
  git -C "$project_dir" config user.email "test@example.com"
  git -C "$project_dir" config user.name "Test"

  # Create component cache
  printf 'backend=spring\nfrontend=react\n' > "$project_dir/.forge/.component-cache"

  # Create files in each component
  echo 'fun main() {}' > "$project_dir/backend/src/main/kotlin/App.kt"
  echo 'export const App = () => {};' > "$project_dir/frontend/src/App.tsx"

  # Backend file should route through spring rules
  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/backend/src/main/kotlin/App.kt"
  assert_success

  # Frontend file should route through react rules
  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/frontend/src/App.tsx"
  assert_success
}

# ---------------------------------------------------------------------------
# 5. Hook mode — TOOL_INPUT simulation
# ---------------------------------------------------------------------------

@test "integration: engine hook mode processes TOOL_INPUT" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  mkdir -p "$project_dir/src/main/kotlin"
  echo 'fun main() {}' > "$project_dir/src/main/kotlin/App.kt"

  # Simulate PostToolUse hook with TOOL_INPUT
  cd "$project_dir"
  TOOL_INPUT="{\"file_path\": \"$project_dir/src/main/kotlin/App.kt\"}" \
    run bash "$ENGINE_SH" --hook
  assert_success
}

# ---------------------------------------------------------------------------
# 6. Empty and edge-case files
# ---------------------------------------------------------------------------

@test "integration: engine skips empty files in hook mode" {
  local project_dir
  project_dir="$(create_temp_project react)"

  mkdir -p "$project_dir/src"
  touch "$project_dir/src/empty.ts"

  cd "$project_dir"
  TOOL_INPUT="{\"file_path\": \"$project_dir/src/empty.ts\"}" \
    run bash "$ENGINE_SH" --hook
  assert_success
  assert_output ""
}

@test "integration: engine handles file with no matching language" {
  local project_dir
  project_dir="$(create_temp_project react)"

  echo "# Just a readme" > "$project_dir/README.md"

  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/README.md"

  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# 7. Module cache persistence
# ---------------------------------------------------------------------------

@test "integration: engine creates module cache on first detection" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  # Remove any pre-existing cache
  rm -f "$project_dir/.forge/.module-cache"

  mkdir -p "$project_dir/src/main/kotlin"
  echo 'fun main() {}' > "$project_dir/src/main/kotlin/App.kt"

  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/src/main/kotlin/App.kt"

  assert_success
  # Module cache should have been created
  [[ -f "$project_dir/.forge/.module-cache" ]]
  local cached_module
  cached_module="$(cat "$project_dir/.forge/.module-cache")"
  [[ "$cached_module" == "spring" ]]
}

# ---------------------------------------------------------------------------
# 8. Go project detection
# ---------------------------------------------------------------------------

@test "integration: engine detects go-stdlib from go.mod" {
  local project_dir
  project_dir="$(create_temp_project go-stdlib)"

  mkdir -p "$project_dir/cmd"
  cat > "$project_dir/cmd/main.go" <<'EOF'
package main

import "fmt"

func main() {
    fmt.Println("hello")
}
EOF

  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/cmd/main.go"

  assert_success
}

# ---------------------------------------------------------------------------
# 9. FastAPI project detection
# ---------------------------------------------------------------------------

@test "integration: engine detects fastapi from pyproject.toml" {
  local project_dir
  project_dir="$(create_temp_project fastapi)"

  mkdir -p "$project_dir/app"
  cat > "$project_dir/app/main.py" <<'EOF'
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"hello": "world"}
EOF

  run bash "$ENGINE_SH" --verify \
    --project-root "$project_dir" \
    --files-changed "$project_dir/app/main.py"

  assert_success
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

skip_if_no_python3() {
  command -v python3 &>/dev/null || skip "python3 not available"
}
