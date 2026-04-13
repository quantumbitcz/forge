# Helper to set up minimal .forge/ directory for hook testing

setup_mock_forge() {
  export FORGE_DIR="${BATS_TEST_TMPDIR}/.forge"
  mkdir -p "$FORGE_DIR/feedback"
  echo '{"story_state":"IMPLEMENTING","version":"1.5.0","mode":"standard","score":75}' \
    > "$FORGE_DIR/state.json"
  # Change to temp dir so hooks find .forge/
  cd "$BATS_TEST_TMPDIR"
}

teardown_mock_forge() {
  rm -rf "${BATS_TEST_TMPDIR}/.forge" 2>/dev/null || true
}
