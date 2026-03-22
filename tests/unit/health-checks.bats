#!/usr/bin/env bats
# Unit tests for shared/recovery/health-checks/pre-stage-health.sh
# and shared/recovery/health-checks/dependency-check.sh

load '../helpers/test-helpers'

PRE_STAGE="$PLUGIN_ROOT/shared/recovery/health-checks/pre-stage-health.sh"
DEP_CHECK="$PLUGIN_ROOT/shared/recovery/health-checks/dependency-check.sh"

# ---------------------------------------------------------------------------
# pre-stage-health.sh tests
# ---------------------------------------------------------------------------

# 1. PREFLIGHT returns OK (git + python3 are available on the test machine)
@test "pre-stage-health: preflight returns OK when git and python3 are available" {
  run bash "$PRE_STAGE" preflight "$TEST_TEMP"
  assert_success
  assert_output "OK"
}

# 2. explore stage returns OK (no required deps)
@test "pre-stage-health: explore stage returns OK with no deps required" {
  run bash "$PRE_STAGE" explore "$TEST_TEMP"
  assert_success
  assert_output "OK"
}

# 3. plan stage returns OK (no required deps)
@test "pre-stage-health: plan stage returns OK with no deps required" {
  run bash "$PRE_STAGE" plan "$TEST_TEMP"
  assert_success
  assert_output "OK"
}

# 4. Unknown stage returns OK with informational message
@test "pre-stage-health: unknown stage returns OK with unknown stage message" {
  run bash "$PRE_STAGE" some-unknown-stage "$TEST_TEMP"
  assert_success
  assert_output --partial "OK"
  assert_output --partial "unknown stage"
}

# 5. No argument outputs MISSING with usage hint
@test "pre-stage-health: no argument outputs MISSING" {
  run bash "$PRE_STAGE"
  assert_success
  assert_output --partial "MISSING"
}

# 6. Case insensitive stage names: PREFLIGHT -> OK
@test "pre-stage-health: stage names are case insensitive (PREFLIGHT -> ok)" {
  run bash "$PRE_STAGE" PREFLIGHT "$TEST_TEMP"
  assert_success
  assert_output "OK"
}

# 7. IMPLEMENT detects git merge in progress (MERGE_HEAD file present)
@test "pre-stage-health: implement reports error when git merge is in progress" {
  local project_dir
  project_dir="$(create_temp_project kotlin-spring)"

  # Create an initial commit so the git repo is valid
  git -C "$project_dir" add .
  git -C "$project_dir" commit -q -m "init"

  # Simulate a merge in progress
  touch "$project_dir/.git/MERGE_HEAD"

  run bash "$PRE_STAGE" implement "$project_dir"
  assert_success
  # Script writes "ERROR: Git merge in progress" to stderr; exit code stays 0
  # bats merges stdout+stderr in $output by default
  assert_output --partial "merge"
}

# 8. IMPLEMENT detects git rebase in progress (rebase-merge dir present)
@test "pre-stage-health: implement reports error when git rebase is in progress" {
  local project_dir
  project_dir="$(create_temp_project kotlin-spring)"

  git -C "$project_dir" add .
  git -C "$project_dir" commit -q -m "init"

  # Simulate a rebase in progress
  mkdir -p "$project_dir/.git/rebase-merge"

  run bash "$PRE_STAGE" implement "$project_dir"
  assert_success
  assert_output --partial "rebase"
}

# ---------------------------------------------------------------------------
# dependency-check.sh tests
# ---------------------------------------------------------------------------

# 9. Unknown dependency reports UNAVAILABLE
@test "dependency-check: unknown dependency reports UNAVAILABLE" {
  run bash "$DEP_CHECK" totally-unknown-dep-xyz
  assert_success
  assert_output --partial "UNAVAILABLE"
  assert_output --partial "unknown dependency"
}

# 10. context7 always returns OK (passive check)
@test "dependency-check: context7 always returns OK" {
  # context7 emits an INFO line to stderr — check only stdout for the OK line
  run bash -c "bash '$DEP_CHECK' context7 2>/dev/null"
  assert_success
  assert_output "OK"
}

# 11. No argument reports UNAVAILABLE
@test "dependency-check: no argument reports UNAVAILABLE" {
  run bash "$DEP_CHECK"
  assert_success
  assert_output --partial "UNAVAILABLE"
}

# 12. Case insensitive: CONTEXT7 -> OK
@test "dependency-check: dependency names are case insensitive (CONTEXT7 -> ok)" {
  # context7 emits an INFO line to stderr — check only stdout for the OK line
  run bash -c "bash '$DEP_CHECK' CONTEXT7 2>/dev/null"
  assert_success
  assert_output "OK"
}

# 13. node check: node is available on test machine -> OK
@test "dependency-check: node check returns OK when node is installed" {
  if ! command -v node &>/dev/null; then
    skip "node not installed on this machine"
  fi
  run bash "$DEP_CHECK" node
  assert_success
  assert_output "OK"
}

# 14. gh check: test UNAVAILABLE path by mocking gh as missing
@test "dependency-check: gh reports UNAVAILABLE when gh command is not found" {
  # Remove any real gh from PATH by creating a mock that doesn't exist
  # We override PATH to a dir that has no 'gh'
  local no_gh_path="${TEST_TEMP}/no-gh-bin"
  mkdir -p "$no_gh_path"
  # Copy only essential commands, exclude gh
  # Simply rely on MOCK_BIN being first and not creating a gh mock there,
  # while ensuring the real gh is shadowed if present.
  mock_command "gh" 'exit 127'
  # Now gh "exists" but if we want UNAVAILABLE we need it to not exist.
  # Instead test with a stripped PATH that has no gh at all.
  local stripped_path
  stripped_path="$(echo "$PATH" | tr ':' '\n' | grep -v "$MOCK_BIN" | tr '\n' ':' | sed 's/:$//')"

  # Remove the mock we just made
  rm -f "${MOCK_BIN}/gh"

  run env PATH="$no_gh_path:/bin:/usr/bin" bash "$DEP_CHECK" gh
  assert_success
  assert_output --partial "UNAVAILABLE"
  assert_output --partial "gh"
}
