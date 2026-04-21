#!/usr/bin/env bats
# Structural tests: guards against bash regression in scripts
# that have been (or should be) ported to Python.
#
# Each ported script must satisfy ONE of:
#   (a) the .sh file is gone and a .py replacement exists, OR
#   (b) the .sh file exists ONLY as a thin shim (≤ 20 lines, exec's python3)

load '../helpers/test-helpers'

# Helper: returns 0 if the file is a thin shim that exec's python3.
# A shim is ≤ 20 non-blank, non-comment lines AND mentions `python3 -m`
# or `exec python3`.
is_thin_shim() {
  local f="$1"
  [[ -f "$f" ]] || return 1

  local code_lines
  code_lines=$(grep -cE '^[[:space:]]*[^[:space:]#]' "$f" || true)
  if [[ "$code_lines" -gt 20 ]]; then
    return 1
  fi

  grep -qE '(python3 -m|exec python3)' "$f"
}

# Helper: assert that a bash script has been ported.
# Args: <bash_path> <python_module_path>
assert_ported() {
  local sh_path="$1"
  local py_path="$2"

  if [[ -f "$sh_path" ]]; then
    if ! is_thin_shim "$sh_path"; then
      fail "$sh_path still contains substantive bash logic — must be removed or replaced with a ≤20-line python3 shim"
    fi
  fi

  assert [ -f "$py_path" ]
}

# ---------------------------------------------------------------------------
# Task 13: config-validator
# ---------------------------------------------------------------------------

@test "Task 13: config-validator is Python" {
  assert_ported \
    "$PLUGIN_ROOT/shared/config-validator.sh" \
    "$PLUGIN_ROOT/shared/config_validator.py"
}

# ---------------------------------------------------------------------------
# Task 14: 4 audit scripts
# ---------------------------------------------------------------------------

@test "Task 14: context-guard is Python" {
  assert_ported \
    "$PLUGIN_ROOT/shared/context-guard.sh" \
    "$PLUGIN_ROOT/shared/context_guard.py"
}

@test "Task 14: cost-alerting is Python" {
  assert_ported \
    "$PLUGIN_ROOT/shared/cost-alerting.sh" \
    "$PLUGIN_ROOT/shared/cost_alerting.py"
}

@test "Task 14: validate-finding is Python" {
  assert_ported \
    "$PLUGIN_ROOT/shared/validate-finding.sh" \
    "$PLUGIN_ROOT/shared/validate_finding.py"
}

@test "Task 14: generate-conventions-index is Python" {
  assert_ported \
    "$PLUGIN_ROOT/shared/generate-conventions-index.sh" \
    "$PLUGIN_ROOT/shared/generate_conventions_index.py"
}

# ---------------------------------------------------------------------------
# Task 15: convergence-engine-sim — port to Python (bash-3.2 compat too hard)
# ---------------------------------------------------------------------------

@test "Task 15: convergence-engine-sim is Python (or bash-3.2 safe)" {
  local sh="$PLUGIN_ROOT/shared/convergence-engine-sim.sh"
  local py="$PLUGIN_ROOT/shared/convergence_engine_sim.py"

  if [[ -f "$py" ]]; then
    return 0
  fi

  # Fallback: still bash, but must not use bash 4+ syntax (declare -A, mapfile, &>>, etc.)
  assert [ -f "$sh" ]
  run grep -nE '\bdeclare -A\b|\bmapfile\b|\breadarray\b|&>>' "$sh"
  assert_failure
}

# ---------------------------------------------------------------------------
# Task 16: tests/validate-plugin Python alternative entry point
#
# Unlike the other ported scripts, validate-plugin.sh remains the canonical
# implementation (it already runs cross-platform via CI). The Python
# version is an additional entry point covering the same checks, intended for
# environments where bash is unavailable or undesirable.
# ---------------------------------------------------------------------------

@test "Task 16: validate_plugin.py exists as Python alternative" {
  assert [ -f "$PLUGIN_ROOT/tests/validate_plugin.py" ]
  # Both implementations must exist; .sh is canonical.
  assert [ -f "$PLUGIN_ROOT/tests/validate-plugin.sh" ]
}

@test "Task 16: validate_plugin.py is invokable" {
  run python3 "$PLUGIN_ROOT/tests/validate_plugin.py" --help
  assert_success
  assert_output --partial "structural validation"
}

# ---------------------------------------------------------------------------
# Task 20: no Python code reads FORGE_OS / FORGE_PYTHON
#
# These env vars are legacy knobs for unported bash scripts (which still need
# them to find Python and branch on OS). Python code must NEVER read them —
# Python detects its OS via platform.system() and runs as sys.executable.
# The Python ports rely on this; future bash retirements will eliminate the
# env vars entirely.
# ---------------------------------------------------------------------------

@test "Task 20: no Python code reads FORGE_OS" {
  local hits
  hits=$(grep -rn 'FORGE_OS' \
    "$PLUGIN_ROOT/shared/" \
    "$PLUGIN_ROOT/hooks/" \
    "$PLUGIN_ROOT/tests/" \
    --include='*.py' \
    2>/dev/null | grep -v '^[^:]*:[0-9]*:#' || true)

  if [[ -n "$hits" ]]; then
    echo "Python code must not read FORGE_OS — use platform.system() instead:"
    echo "$hits"
    fail "FORGE_OS forbidden in Python code"
  fi
}

@test "Task 20: no Python code reads FORGE_PYTHON" {
  local hits
  hits=$(grep -rn 'FORGE_PYTHON' \
    "$PLUGIN_ROOT/shared/" \
    "$PLUGIN_ROOT/hooks/" \
    "$PLUGIN_ROOT/tests/" \
    --include='*.py' \
    2>/dev/null | grep -v '^[^:]*:[0-9]*:#' || true)

  if [[ -n "$hits" ]]; then
    echo "Python code must not read FORGE_PYTHON — use sys.executable instead:"
    echo "$hits"
    fail "FORGE_PYTHON forbidden in Python code"
  fi
}

# ---------------------------------------------------------------------------
# General: hooks/ contains no bash logic — production hooks are Python
# ---------------------------------------------------------------------------

@test "hooks/ contains no .sh files" {
  local sh_files
  sh_files=$(find "$PLUGIN_ROOT/hooks" -maxdepth 2 -name '*.sh' -type f 2>/dev/null || true)

  if [[ -n "$sh_files" ]]; then
    echo "Found unexpected .sh in hooks/:"
    echo "$sh_files"
    fail "All hooks must be Python. Add new hooks as hooks/_py/<name>.py"
  fi
}
