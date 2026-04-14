#!/usr/bin/env bats
# Structural tests: cross-platform portability invariants

load '../helpers/test-helpers'

@test "all mktemp calls use full temp cascade (TMPDIR/TMP/TEMP)" {
  local violations
  violations=$(grep -rn 'TMPDIR:-/tmp}' \
    "$PLUGIN_ROOT/shared/" \
    "$PLUGIN_ROOT/hooks/" \
    --include='*.sh' \
    | grep -v 'TMPDIR:-\${TMP:-' \
    | grep -v '# inline pattern' \
    | grep -v 'tests/' || true)

  if [[ -n "$violations" ]]; then
    echo "Found incomplete temp cascades (missing TMP/TEMP fallback):"
    echo "$violations"
    fail "All mktemp calls must use \${TMPDIR:-\${TMP:-\${TEMP:-/tmp}}}"
  fi
}

@test ".gitattributes enforces LF for .bats files" {
  local gitattr="$PLUGIN_ROOT/.gitattributes"
  assert [ -f "$gitattr" ]
  run grep '^\*\.bats' "$gitattr"
  assert_success
  assert_output --partial "eol=lf"
}

@test "platform-support.md exists" {
  assert [ -f "$PLUGIN_ROOT/shared/platform-support.md" ]
}

@test "platform-support.md contains required sections" {
  local doc="$PLUGIN_ROOT/shared/platform-support.md"
  run grep '## Supported Platforms' "$doc"
  assert_success
  run grep '## Required Tools' "$doc"
  assert_success
  run grep '## Per-Platform Setup' "$doc"
  assert_success
  run grep '## Known Limitations' "$doc"
  assert_success
  run grep '## Configuration' "$doc"
  assert_success
}

@test "platform-support.md documents all supported platforms" {
  local doc="$PLUGIN_ROOT/shared/platform-support.md"
  run grep -c 'macOS\|Ubuntu\|Fedora\|Arch\|Alpine\|WSL2\|Git Bash' "$doc"
  assert_success
  [[ "${output}" -ge 7 ]]
}

@test "no compgen calls in source files (only comments)" {
  local violations
  violations=$(grep -rn 'compgen ' \
    "$PLUGIN_ROOT/shared/" \
    "$PLUGIN_ROOT/hooks/" \
    --include='*.sh' \
    | grep -v '^[^:]*:[^:]*:#' \
    | grep -v 'tests/' || true)
  if [[ -n "$violations" ]]; then
    echo "Found compgen calls (should use _glob_exists):"
    echo "$violations"
    fail "No compgen calls allowed — use _glob_exists() instead"
  fi
}

@test "no readlink -f calls in source files" {
  local violations
  violations=$(grep -rn 'readlink -f\|readlink --canonicalize' \
    "$PLUGIN_ROOT/shared/" \
    "$PLUGIN_ROOT/hooks/" \
    --include='*.sh' \
    | grep -v 'tests/' || true)
  if [[ -n "$violations" ]]; then
    echo "Found readlink -f calls (should use portable_normalize_path):"
    echo "$violations"
    fail "No readlink -f calls allowed — use portable_normalize_path() instead"
  fi
}

@test "all flock calls are guarded by command -v flock" {
  local violations=0
  while IFS= read -r -d '' script; do
    # Find lines that call the shell flock command (not mentions in comments or strings)
    local flock_lines
    flock_lines=$(grep -n 'flock ' "$script" \
      | grep -v '#.*flock' \
      | grep -v 'command -v flock' \
      | grep -v 'fcntl\.flock' \
      || true)
    if [[ -n "$flock_lines" ]]; then
      local has_guard
      has_guard=$(grep -c 'command -v flock' "$script" || true)
      if [[ "$has_guard" -eq 0 ]]; then
        echo "UNGUARDED flock in $script:"
        echo "$flock_lines"
        violations=$((violations + 1))
      fi
    fi
  done < <(find "$PLUGIN_ROOT/shared" "$PLUGIN_ROOT/hooks" -name '*.sh' -print0)
  [[ "$violations" -eq 0 ]]
}

@test "no unconditional fcntl import in inline Python" {
  local violations=0
  while IFS= read -r -d '' script; do
    # Find files that have 'import fcntl' without a try/except guard in proximity
    if grep -q 'import fcntl' "$script" 2>/dev/null; then
      # Check that each occurrence of 'import fcntl' has a 'try:' somewhere in the file
      local has_try
      has_try=$(grep -c 'try:' "$script" || true)
      if [[ "$has_try" -eq 0 ]]; then
        echo "UNGUARDED fcntl import in $script (no try/except found)"
        violations=$((violations + 1))
      fi
    fi
  done < <(find "$PLUGIN_ROOT/shared" "$PLUGIN_ROOT/hooks" -name '*.sh' -print0)
  if [[ "$violations" -gt 0 ]]; then
    fail "Python fcntl imports must use try/except with msvcrt fallback"
  fi
}
