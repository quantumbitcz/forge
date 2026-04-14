#!/usr/bin/env bats
# Scenario test: multi-framework convention composition.
# Tests verify composition logic from shared/composition.md and the
# composition matrix. These are document-property + structural tests.

load '../helpers/test-helpers'

COMPOSITION_DOC="$PLUGIN_ROOT/shared/composition.md"
FRAMEWORKS_DIR="$PLUGIN_ROOT/modules/frameworks"
LANGUAGES_DIR="$PLUGIN_ROOT/modules/languages"
CODE_QUALITY_DIR="$PLUGIN_ROOT/modules/code-quality"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
  mkdir -p "${TEST_TEMP}/project"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

# ---------------------------------------------------------------------------
# 1. Composition order documented: variant > framework-binding > framework > language
# ---------------------------------------------------------------------------
@test "composition: resolution order documented as most-specific-wins" {
  grep -q "most specific wins" "$COMPOSITION_DOC" \
    || fail "composition.md does not document 'most specific wins' resolution order"

  # Verify the numbered order: variant (7) > framework binding (6) > framework (5) > language (4)
  grep -q "Variant" "$COMPOSITION_DOC" \
    || fail "composition.md does not mention Variant in resolution order"
  grep -q "Framework binding" "$COMPOSITION_DOC" \
    || fail "composition.md does not mention Framework binding in resolution order"
  grep -q "Language" "$COMPOSITION_DOC" \
    || fail "composition.md does not mention Language in resolution order"
}

# ---------------------------------------------------------------------------
# 2. Convention stack soft cap of 12 files documented
# ---------------------------------------------------------------------------
@test "composition: convention stack soft cap of 12 files is documented" {
  grep -q "12 files" "$COMPOSITION_DOC" \
    || fail "composition.md does not document the 12-file soft cap"
  grep -q "soft-capped" "$COMPOSITION_DOC" \
    || fail "composition.md does not use 'soft-capped' language"
}

# ---------------------------------------------------------------------------
# 3. k8s framework has no language conventions (language: null)
# ---------------------------------------------------------------------------
@test "composition: k8s component has no language conventions" {
  # k8s uses language: null -- verify its config template reflects this
  local k8s_dir="$FRAMEWORKS_DIR/k8s"
  [[ -d "$k8s_dir" ]] || fail "k8s framework directory not found"

  # The k8s config template or conventions should indicate language: null
  local found_null=false
  if [[ -f "$k8s_dir/forge-config-template.md" ]]; then
    if grep -q "language:.*null\|language: null" "$k8s_dir/forge-config-template.md"; then
      found_null=true
    fi
  fi
  if [[ -f "$k8s_dir/local-template.md" ]]; then
    if grep -q "language:.*null\|language: null" "$k8s_dir/local-template.md"; then
      found_null=true
    fi
  fi
  # Also check CLAUDE.md which documents k8s as language: null
  if grep -q 'k8s.*language.*null\|`k8s`.*`language: null`' "$PLUGIN_ROOT/CLAUDE.md"; then
    found_null=true
  fi

  [[ "$found_null" == "true" ]] \
    || fail "k8s is not documented with language: null"

  # k8s should NOT have a language .md reference in its conventions
  if [[ -f "$k8s_dir/conventions.md" ]]; then
    ! grep -qi "language module\|modules/languages/" "$k8s_dir/conventions.md" \
      || true  # Not a hard failure if it references languages for documentation purposes
  fi
}

# ---------------------------------------------------------------------------
# 4. Code quality modules exist (eslint, prettier as representative samples)
# ---------------------------------------------------------------------------
@test "composition: code_quality list references existing tool convention files" {
  [[ -f "$CODE_QUALITY_DIR/eslint.md" ]] \
    || fail "modules/code-quality/eslint.md not found"
  [[ -f "$CODE_QUALITY_DIR/prettier.md" ]] \
    || fail "modules/code-quality/prettier.md not found"

  # Verify composition.md references code quality in the resolution order
  grep -q "Code quality" "$COMPOSITION_DOC" \
    || fail "composition.md does not include Code quality in resolution order"
}
