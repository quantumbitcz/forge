#!/usr/bin/env bats
# Contract tests: shell script permissions and hygiene.

load '../helpers/test-helpers'

# Directories to search for .sh files
SEARCH_DIRS=(
  "$PLUGIN_ROOT/shared"
  "$PLUGIN_ROOT/hooks"
  "$PLUGIN_ROOT/modules"
)

# Critical scripts that must exist and be executable
CRITICAL_SCRIPTS=(
  "$PLUGIN_ROOT/shared/checks/engine.sh"
  "$PLUGIN_ROOT/shared/checks/layer-1-fast/run-patterns.sh"
  "$PLUGIN_ROOT/shared/checks/layer-2-linter/run-linter.sh"
)

# ---------------------------------------------------------------------------
# Helper: collect all .sh files from SEARCH_DIRS
# ---------------------------------------------------------------------------
_all_scripts() {
  find "${SEARCH_DIRS[@]}" -name "*.sh" -type f 2>/dev/null
}

# ---------------------------------------------------------------------------
# 1. All .sh files in shared/ and hooks/ have a shebang line
# ---------------------------------------------------------------------------
@test "script-permissions: all .sh files have shebang on line 1" {
  local failures=()
  while IFS= read -r script; do
    local first_line
    first_line="$(head -1 "$script")"
    if ! printf '%s' "$first_line" | grep -qE '^#!'; then
      failures+=("${script#"$PLUGIN_ROOT/"}")
    fi
  done < <(_all_scripts)
  if (( ${#failures[@]} > 0 )); then
    fail "Scripts missing shebang: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. All .sh files are executable
# ---------------------------------------------------------------------------
@test "script-permissions: all .sh files are executable" {
  local failures=()
  while IFS= read -r script; do
    if [[ ! -x "$script" ]]; then
      failures+=("${script#"$PLUGIN_ROOT/"}")
    fi
  done < <(_all_scripts)
  if (( ${#failures[@]} > 0 )); then
    fail "Scripts not executable: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. No CRLF line endings in .sh files
# ---------------------------------------------------------------------------
@test "script-permissions: no CRLF line endings in .sh files" {
  local failures=()
  while IFS= read -r script; do
    if grep -q $'\r' "$script" 2>/dev/null; then
      failures+=("${script#"$PLUGIN_ROOT/"}")
    fi
  done < <(_all_scripts)
  if (( ${#failures[@]} > 0 )); then
    fail "Scripts with CRLF line endings: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. Critical scripts exist and are executable
# ---------------------------------------------------------------------------
@test "script-permissions: critical scripts exist and are executable" {
  local failures=()
  for script in "${CRITICAL_SCRIPTS[@]}"; do
    if [[ ! -f "$script" ]]; then
      failures+=("${script#"$PLUGIN_ROOT/"}: missing")
    elif [[ ! -x "$script" ]]; then
      failures+=("${script#"$PLUGIN_ROOT/"}: not executable")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Critical script issues: ${failures[*]}"
  fi
}
