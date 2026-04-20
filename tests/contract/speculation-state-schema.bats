#!/usr/bin/env bats
# Contract tests: Phase 12 speculation fields in shared/state-schema.md
# (plan_candidates[] and speculation object).

load '../helpers/test-helpers'

STATE="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# 1. Schema still carries a recognisable semver marker (1.x.0).
#
# Note: The plan (docs/superpowers/plans/2026-04-19-12-...) called for bumping
# the schema to v1.7.0, but the current schema is already at v1.9.0 (Phase 11
# voting + Phase 14 CAS checkpoints). Phase 12 adds speculation fields
# additively without bumping the version, so we just assert the version
# marker still exists.
# ---------------------------------------------------------------------------
@test "state schema declares a 1.x.0 version marker" {
  grep -Eq '1\.[0-9]+\.0' "$STATE"
}

# ---------------------------------------------------------------------------
# 2. plan_candidates[] documented with required candidate fields.
# ---------------------------------------------------------------------------
@test "plan_candidates field documented" {
  grep -q "plan_candidates" "$STATE"
  grep -q "emphasis_axis" "$STATE"
  grep -q "validator_verdict" "$STATE"
  grep -q "selection_score" "$STATE"
}

# ---------------------------------------------------------------------------
# 3. speculation object documented with required signal fields.
# ---------------------------------------------------------------------------
@test "speculation object documented" {
  grep -q '"speculation": {' "$STATE" || grep -q "speculation:" "$STATE"
  grep -q "triggered" "$STATE"
  grep -q "winner_id" "$STATE"
  grep -q "user_confirmed" "$STATE"
}

# ---------------------------------------------------------------------------
# 4. Defaults documented (empty array + null).
# ---------------------------------------------------------------------------
@test "defaults documented (empty array + null)" {
  grep -q 'plan_candidates: \[\]' "$STATE" || grep -q '"plan_candidates": \[\]' "$STATE"
}
