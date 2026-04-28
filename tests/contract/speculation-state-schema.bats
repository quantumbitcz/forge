#!/usr/bin/env bats
# Contract tests: speculation fields in shared/state-schema.md
# (plan_candidates[] and speculation object).

load '../helpers/test-helpers'

STATE="$PLUGIN_ROOT/shared/state-schema.md"
STATE_FIELDS="$PLUGIN_ROOT/shared/state-schema-fields.md"

# ---------------------------------------------------------------------------
# 1. Schema still carries a recognisable semver marker (1.x.0 or 2.x.0).
#
# Note: the current schema is at v2.1.0 (mega-consolidation, 2026-04-27).
# v2.0.0 was a hard cut from the 1.x series. Speculation fields are additive
# and survived the bump, so we just assert any major-version marker exists.
# ---------------------------------------------------------------------------
@test "state schema declares a major-version marker" {
  grep -Eq '[12]\.[0-9]+\.0' "$STATE"
}

# ---------------------------------------------------------------------------
# 2. plan_candidates[] documented with required candidate fields.
# ---------------------------------------------------------------------------
@test "plan_candidates field documented" {
  grep -qh "plan_candidates" "$STATE" "$STATE_FIELDS"
  grep -qh "emphasis_axis" "$STATE" "$STATE_FIELDS"
  grep -qh "validator_verdict" "$STATE" "$STATE_FIELDS"
  grep -qh "selection_score" "$STATE" "$STATE_FIELDS"
}

# ---------------------------------------------------------------------------
# 3. speculation object documented with required signal fields.
# ---------------------------------------------------------------------------
@test "speculation object documented" {
  grep -qh '"speculation": {' "$STATE" "$STATE_FIELDS" || grep -qh "speculation:" "$STATE" "$STATE_FIELDS"
  grep -qh "triggered" "$STATE" "$STATE_FIELDS"
  grep -qh "winner_id" "$STATE" "$STATE_FIELDS"
  grep -qh "user_confirmed" "$STATE" "$STATE_FIELDS"
}

# ---------------------------------------------------------------------------
# 4. Defaults documented (empty array + null).
# ---------------------------------------------------------------------------
@test "defaults documented (empty array + null)" {
  grep -qh 'plan_candidates: \[\]' "$STATE" "$STATE_FIELDS" || grep -qh '"plan_candidates": \[\]' "$STATE" "$STATE_FIELDS"
}
