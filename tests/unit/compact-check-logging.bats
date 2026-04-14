#!/usr/bin/env bats
# Unit test: forge-compact-check.sh logs errors to .hook-failures.log

load '../helpers/test-helpers'

COMPACT_CHECK="$PLUGIN_ROOT/shared/forge-compact-check.sh"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}" "${TEST_TEMP}/.forge"
  export PATH="${MOCK_BIN}:${PATH}"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "compact-check-logging: logs failure when increment fails" {
  # Override atomic_increment to always fail (return empty)
  atomic_increment() { return 1; }
  export -f atomic_increment

  # Also mock flock to fail (fallback path)
  cat > "${MOCK_BIN}/flock" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${MOCK_BIN}/flock"

  # Run the compact check — it should still exit 0 (best-effort)
  run bash "$COMPACT_CHECK" --forge-dir "${TEST_TEMP}/.forge"
  assert_success

  # Verify failure was logged
  # compact-check logs to forge.log (per SPEC-02 revision)
  [[ -f "${TEST_TEMP}/.forge/forge.log" ]] || [[ -f "${TEST_TEMP}/.forge/.hook-failures.log" ]] || \
    fail "No forge.log or .hook-failures.log created"
  local log_file
  if [[ -f "${TEST_TEMP}/.forge/forge.log" ]]; then
    log_file="${TEST_TEMP}/.forge/forge.log"
  else
    log_file="${TEST_TEMP}/.forge/.hook-failures.log"
  fi
  grep -q "compact-check\|COMPACT" "$log_file" || \
    fail "Log does not contain compact-check entry"
}

@test "compact-check-logging: exits 0 even on failure" {
  atomic_increment() { return 1; }
  export -f atomic_increment
  run bash "$COMPACT_CHECK" --forge-dir "${TEST_TEMP}/.forge"
  assert_success
}
