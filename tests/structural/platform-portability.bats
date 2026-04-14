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
