#!/usr/bin/env bats
# Unit tests: evidence staleness window — validates the effective staleness
# window calculation and loop cap documented in verification-evidence.md.

load '../helpers/test-helpers'

EVIDENCE_DOC="$PLUGIN_ROOT/shared/verification-evidence.md"
STATE_TRANSITIONS="$PLUGIN_ROOT/shared/state-transitions.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# Helper: compute effective staleness window
# Uses the formula: max(evidence_max_age_minutes, generation_duration + 5)
# ---------------------------------------------------------------------------
compute_effective_window() {
  local evidence_max_age="${1:?}" generation_duration="${2:?}"
  local extended=$(( generation_duration + 5 ))
  if [[ $evidence_max_age -ge $extended ]]; then
    echo "$evidence_max_age"
  else
    echo "$extended"
  fi
}

# Helper: check if evidence is stale
# Returns 0 (true/stale) or 1 (false/fresh)
is_stale() {
  local evidence_age="${1:?}" effective_window="${2:?}"
  [[ $evidence_age -gt $effective_window ]]
}

# ---------------------------------------------------------------------------
# 1. Fresh evidence within default window
# ---------------------------------------------------------------------------
@test "evidence-staleness: fresh evidence within default window" {
  local window
  window=$(compute_effective_window 30 5)
  assert_equal "$window" "30"
  run is_stale 10 "$window"
  assert_failure
}

# ---------------------------------------------------------------------------
# 2. Stale evidence outside default window
# ---------------------------------------------------------------------------
@test "evidence-staleness: stale evidence outside default window" {
  local window
  window=$(compute_effective_window 30 5)
  assert_equal "$window" "30"
  run is_stale 35 "$window"
  assert_success
}

# ---------------------------------------------------------------------------
# 3. Slow build extends effective window
# ---------------------------------------------------------------------------
@test "evidence-staleness: slow build extends effective window" {
  local window
  window=$(compute_effective_window 30 40)
  assert_equal "$window" "45"
  run is_stale 42 "$window"
  assert_failure
}

# ---------------------------------------------------------------------------
# 4. Effective window never below configured minimum
# ---------------------------------------------------------------------------
@test "evidence-staleness: effective window never below configured minimum" {
  local window
  window=$(compute_effective_window 30 2)
  assert_equal "$window" "30"
}

# ---------------------------------------------------------------------------
# 5. Loop cap at 3 refreshes — row 52 in transition table
# ---------------------------------------------------------------------------
@test "evidence-staleness: loop cap at 3 refreshes documented" {
  grep -qE "evidence_refresh_count >= 3|evidence_stale AND evidence_refresh_count" "$STATE_TRANSITIONS" \
    || fail "Row 52 (evidence refresh loop cap) not found in state-transitions.md"
}

# ---------------------------------------------------------------------------
# 6. generation_started_at field documented in evidence schema
# ---------------------------------------------------------------------------
@test "evidence-staleness: generation_started_at field documented" {
  grep -q "generation_started_at" "$EVIDENCE_DOC" \
    || fail "generation_started_at field not documented in verification-evidence.md"
}

# ---------------------------------------------------------------------------
# 7. Effective staleness window formula documented
# ---------------------------------------------------------------------------
@test "evidence-staleness: effective staleness window formula documented" {
  grep -q "generation_duration" "$EVIDENCE_DOC" \
    || fail "generation_duration not documented in verification-evidence.md"
  grep -q "effective_window\|effective.*window" "$EVIDENCE_DOC" \
    || fail "effective_window formula not documented in verification-evidence.md"
}

# ---------------------------------------------------------------------------
# 8. evidence_refresh_count in state schema
# ---------------------------------------------------------------------------
@test "evidence-staleness: evidence_refresh_count in state schema" {
  grep -q "evidence_refresh_count" "$STATE_SCHEMA" \
    || fail "evidence_refresh_count not documented in state-schema.md"
}

# ---------------------------------------------------------------------------
# 9. Boundary: evidence age exactly at window edge is fresh
# ---------------------------------------------------------------------------
@test "evidence-staleness: evidence at exact window boundary is fresh" {
  run is_stale 30 30
  assert_failure
}

# ---------------------------------------------------------------------------
# 10. Custom small window with fast build
# ---------------------------------------------------------------------------
@test "evidence-staleness: custom small window 5min with 1min build" {
  local window
  window=$(compute_effective_window 5 1)
  assert_equal "$window" "6"
}
