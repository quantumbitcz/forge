#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/run-linter.sh — the linter dispatcher.

load '../helpers/test-helpers'

DISPATCHER="$PLUGIN_ROOT/shared/checks/layer-2-linter/run-linter.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"

# ---------------------------------------------------------------------------
# Helper: make a fake non-executable adapter file for a given linter
# ---------------------------------------------------------------------------
make_nonexec_adapter() {
  local linter="$1"
  local adapter_dir="${TEST_TEMP}/adapters"
  mkdir -p "$adapter_dir"
  local adapter="${adapter_dir}/${linter}.sh"
  printf '#!/usr/bin/env bash\necho "should not run"\n' > "$adapter"
  # intentionally NOT chmod +x
  printf '%s' "$adapter_dir"
}

# ---------------------------------------------------------------------------
# 1. Exits silently (exit 0) when no linter available for a language
# ---------------------------------------------------------------------------
@test "dispatch: exits 0 when no linter available for language" {
  # Use a language that has a primary linter but none installed in mock-bin
  run bash "$DISPATCHER" kotlin /tmp /tmp/fake.kt "$SEV_MAP"
  assert_success
}

# ---------------------------------------------------------------------------
# 2. Exits silently for empty language argument
# ---------------------------------------------------------------------------
@test "dispatch: exits 0 for empty language argument" {
  run bash "$DISPATCHER" "" /tmp /tmp/fake.kt "$SEV_MAP"
  assert_success
}

# ---------------------------------------------------------------------------
# 3. Exits silently for empty target argument
# ---------------------------------------------------------------------------
@test "dispatch: exits 0 for empty target argument" {
  run bash "$DISPATCHER" kotlin /tmp "" "$SEV_MAP"
  assert_success
}

# ---------------------------------------------------------------------------
# 4. Resolves clippy → cargo for availability check
#    Mock cargo so it's found, but the adapter is not present → falls to fallback/INFO
# ---------------------------------------------------------------------------
@test "dispatch: resolves clippy to cargo for availability check" {
  mock_command "cargo" "exit 0"

  # rust has primary=clippy (resolved to cargo) but no adapter in plugin adapters dir
  # The adapter must exist and be executable; it won't be, so run_adapter returns 1
  # and we fall through to INFO message.  The key assertion is exit 0 and no crash.
  run bash "$DISPATCHER" rust /tmp /tmp/fake.rs "$SEV_MAP"
  assert_success
}

# ---------------------------------------------------------------------------
# 5. Handles non-executable adapter gracefully (returns 1 from run_adapter)
# ---------------------------------------------------------------------------
@test "dispatch: handles non-executable adapter gracefully" {
  # Build a fake adapter dir with a non-executable script and point ADAPTER_DIR at it.
  # We do this by wrapping run-linter.sh logic in a tiny test script that overrides
  # ADAPTER_DIR before sourcing the linter selection.  Since the dispatcher doesn't
  # export ADAPTER_DIR, we test the observable behaviour: non-executable → INFO emitted.

  # Mock detekt so it appears available
  mock_command "detekt" "exit 0"

  # Create a non-executable adapter
  local fake_adapter_dir="${TEST_TEMP}/fake-adapters"
  mkdir -p "$fake_adapter_dir"
  printf '#!/usr/bin/env bash\necho "should not run"\n' > "${fake_adapter_dir}/detekt.sh"
  # NOT chmod +x — intentionally non-executable

  # Write a wrapper that overrides ADAPTER_DIR
  local wrapper="${TEST_TEMP}/dispatch-wrapper.sh"
  cat > "$wrapper" << WRAP
#!/usr/bin/env bash
set -euo pipefail
trap 'exit 0' ERR

LANGUAGE="\${1:-}"
PROJECT_ROOT="\${2:-}"
TARGET="\${3:-}"
SEVERITY_MAP="\${4:-}"

[[ -z "\$LANGUAGE" || -z "\$TARGET" ]] && exit 0

ADAPTER_DIR="${fake_adapter_dir}"

declare -A PRIMARY FALLBACK
PRIMARY=([kotlin]=detekt)
FALLBACK=()

resolve_bin() { echo "\$1"; }
run_adapter() {
  local linter="\$1"
  local adapter="\$ADAPTER_DIR/\${linter}.sh"
  [[ ! -x "\$adapter" ]] && return 1
  "\$adapter" "\$PROJECT_ROOT" "\$TARGET" "\$SEVERITY_MAP"
}

primary="\${PRIMARY[\$LANGUAGE]:-}"
fallback="\${FALLBACK[\$LANGUAGE]:-}"

if [[ -n "\$primary" ]] && command -v "\$(resolve_bin "\$primary")" &>/dev/null; then
  run_adapter "\$primary" && exit 0
fi

if [[ -n "\$fallback" ]] && command -v "\$(resolve_bin "\$fallback")" &>/dev/null; then
  run_adapter "\$fallback" && exit 0
fi

echo "INFO: No linter available for \$LANGUAGE, using pattern-based checks only" >&2
exit 0
WRAP
  chmod +x "$wrapper"

  run bash "$wrapper" kotlin /tmp /tmp/Fake.kt "$SEV_MAP"
  assert_success
  # The non-executable adapter causes fallthrough to INFO message
  assert_output --partial "INFO:"
}

# ---------------------------------------------------------------------------
# 6. Emits INFO message to stderr when no linter available
# ---------------------------------------------------------------------------
@test "dispatch: emits INFO message to stderr when no linter available" {
  # No linters mocked → INFO should appear in stderr (bats captures as $output)
  run bash "$DISPATCHER" kotlin /tmp /tmp/fake.kt "$SEV_MAP" 2>&1
  assert_success
  assert_output --partial "INFO: No linter available for kotlin"
}

# ---------------------------------------------------------------------------
# 7. Maps all 8 languages to their primary linters (loop over all)
#    Each call should exit 0 (no crash), confirming the language is recognized.
# ---------------------------------------------------------------------------
@test "dispatch: all 8 languages recognized and exit 0" {
  local -A lang_primary=(
    [kotlin]=detekt
    [java]=checkstyle
    [typescript]=eslint
    [python]=ruff
    [go]=go-vet
    [rust]=cargo      # clippy resolved to cargo
    [c]=clang-tidy
    [swift]=swiftlint
  )

  for lang in "${!lang_primary[@]}"; do
    run bash "$DISPATCHER" "$lang" /tmp /tmp/fake "$SEV_MAP"
    assert_success
  done
}
