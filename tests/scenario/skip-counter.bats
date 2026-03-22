#!/usr/bin/env bats
# Scenario tests: skip counter mechanism in the check engine

load '../helpers/test-helpers'

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-skip-counter.XXXXXX")"
  MOCK_BIN="$TEST_TEMP/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
  git init -q "$TEST_TEMP/project"
  git -C "$TEST_TEMP/project" config user.email "t@t.com"
  git -C "$TEST_TEMP/project" config user.name "T"
}

teardown() { rm -rf "$TEST_TEMP"; }

# Helper: build a skip-trigger wrapper that replicates handle_skip from engine.sh
_make_skip_wrapper() {
  local wrapper="$1"
  cat > "$wrapper" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
handle_skip() {
  local skip_file=".pipeline/.check-engine-skipped"
  if [ -d ".pipeline" ]; then
    local count=0
    if [ -f "$skip_file" ]; then
      count=$(cat "$skip_file" 2>/dev/null || echo 0)
    fi
    echo $((count + 1)) > "$skip_file"
  fi
  echo "[check-engine] Hook skipped (timeout/error)" >&2
  exit 0
}
trap handle_skip ERR
/this/command/does/not/exist
WRAPPER_EOF
  chmod +x "$wrapper"
}

# ---------------------------------------------------------------------------
# 1. Counter created with value 1 on first skip
# ---------------------------------------------------------------------------
@test "skip-counter: first skip creates counter file with value 1" {
  local proj="$TEST_TEMP/project"
  mkdir -p "$proj/.pipeline"
  local wrapper="$TEST_TEMP/skip-wrapper.sh"
  _make_skip_wrapper "$wrapper"

  run bash -c "cd '$proj' && bash '$wrapper'"

  assert_success
  assert [ -f "$proj/.pipeline/.check-engine-skipped" ]
  local count
  count="$(cat "$proj/.pipeline/.check-engine-skipped")"
  assert [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 2. Counter incremented on second skip
# ---------------------------------------------------------------------------
@test "skip-counter: second skip increments counter to 2" {
  local proj="$TEST_TEMP/project"
  mkdir -p "$proj/.pipeline"
  local wrapper="$TEST_TEMP/skip-wrapper.sh"
  _make_skip_wrapper "$wrapper"

  # First skip
  bash -c "cd '$proj' && bash '$wrapper'" >/dev/null 2>&1 || true
  # Second skip
  run bash -c "cd '$proj' && bash '$wrapper'"

  assert_success
  local count
  count="$(cat "$proj/.pipeline/.check-engine-skipped")"
  assert [ "$count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# 3. Counter file absent → created fresh with value 1
# ---------------------------------------------------------------------------
@test "skip-counter: missing counter file is created fresh on first skip" {
  local proj="$TEST_TEMP/project"
  mkdir -p "$proj/.pipeline"
  local skip_file="$proj/.pipeline/.check-engine-skipped"
  # Ensure no pre-existing counter file
  rm -f "$skip_file"
  local wrapper="$TEST_TEMP/skip-wrapper.sh"
  _make_skip_wrapper "$wrapper"

  run bash -c "cd '$proj' && bash '$wrapper'"

  assert_success
  assert [ -f "$skip_file" ]
  local count
  count="$(cat "$skip_file")"
  assert [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 4. No .pipeline/ dir → counter not created
# ---------------------------------------------------------------------------
@test "skip-counter: without .pipeline/ directory no counter file is created" {
  local proj="$TEST_TEMP/project"
  # Do NOT create .pipeline/
  rm -rf "$proj/.pipeline"
  local wrapper="$TEST_TEMP/skip-wrapper.sh"
  _make_skip_wrapper "$wrapper"

  run bash -c "cd '$proj' && bash '$wrapper'"

  assert_success
  assert [ ! -d "$proj/.pipeline" ]
}
