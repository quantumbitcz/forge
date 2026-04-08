#!/usr/bin/env bats
# Contract tests for shared/verification-evidence.md

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
EVIDENCE="$ROOT/shared/verification-evidence.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "verification-evidence: document exists" {
  [ -f "$EVIDENCE" ]
}

# ---------------------------------------------------------------------------
# 2. Schema section with JSON example exists
# ---------------------------------------------------------------------------
@test "verification-evidence: schema section with JSON example exists" {
  grep -q "## Schema" "$EVIDENCE"
  grep -q '"evidence"' "$EVIDENCE"
  grep -q '"verdict"' "$EVIDENCE"
}

# ---------------------------------------------------------------------------
# 3. Field Reference table exists with required fields
# ---------------------------------------------------------------------------
@test "verification-evidence: field reference table documents required fields" {
  grep -q "## Field Reference" "$EVIDENCE"
  for field in timestamp build.command build.exit_code tests.exit_code tests.failed lint.exit_code review.critical_issues review.important_issues score.current verdict block_reasons; do
    grep -q "$field" "$EVIDENCE" || fail "Missing field: $field"
  done
}

# ---------------------------------------------------------------------------
# 4. Verdict Rules section exists with all SHIP conditions
# ---------------------------------------------------------------------------
@test "verification-evidence: verdict rules document all SHIP conditions" {
  grep -q "## Verdict Rules" "$EVIDENCE"
  grep -q "build.exit_code == 0" "$EVIDENCE"
  grep -q "tests.failed == 0" "$EVIDENCE"
  grep -q "lint.exit_code == 0" "$EVIDENCE"
  grep -q "review.critical_issues == 0" "$EVIDENCE"
  grep -q "score.current >= shipping.min_score" "$EVIDENCE"
}

# ---------------------------------------------------------------------------
# 5. BLOCK verdict documented
# ---------------------------------------------------------------------------
@test "verification-evidence: BLOCK verdict with block_reasons documented" {
  grep -qi 'verdict.*BLOCK' "$EVIDENCE"
  grep -q "block_reasons" "$EVIDENCE"
}

# ---------------------------------------------------------------------------
# 6. Staleness section exists with evidence_max_age_minutes
# ---------------------------------------------------------------------------
@test "verification-evidence: staleness rules documented" {
  grep -q "## Staleness" "$EVIDENCE"
  grep -q "evidence_max_age_minutes" "$EVIDENCE"
}

# ---------------------------------------------------------------------------
# 7. Lifecycle section exists documenting fg-590 and fg-600
# ---------------------------------------------------------------------------
@test "verification-evidence: lifecycle documents fg-590 and fg-600 roles" {
  grep -q "## Lifecycle" "$EVIDENCE"
  grep -q "fg-590" "$EVIDENCE"
  grep -q "fg-600" "$EVIDENCE"
}

# ---------------------------------------------------------------------------
# 8. File location documented
# ---------------------------------------------------------------------------
@test "verification-evidence: evidence file location documented" {
  grep -q ".forge/evidence.json" "$EVIDENCE"
}
