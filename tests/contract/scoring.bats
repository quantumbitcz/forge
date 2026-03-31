#!/usr/bin/env bats
# Contract tests: shared/scoring.md — validates the quality scoring document.

load '../helpers/test-helpers'

SCORING="$PLUGIN_ROOT/shared/scoring.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "scoring: document exists" {
  [[ -f "$SCORING" ]]
}

# ---------------------------------------------------------------------------
# 2. Scoring formula documented: 100 - 20 * CRITICAL - 5 * WARNING - 2 * INFO
# ---------------------------------------------------------------------------
@test "scoring: formula documented with correct weights" {
  grep -q "100 - 20" "$SCORING" || fail "Formula base '100 - 20' not found"
  grep -q "\* CRITICAL" "$SCORING" || fail "CRITICAL weight factor not found"
  grep -q "\* WARNING" "$SCORING" || fail "WARNING weight factor not found"
  grep -q "\* INFO" "$SCORING"    || fail "INFO weight factor not found"
}

# ---------------------------------------------------------------------------
# 3. PASS threshold: score >= 80 AND 0 CRITICALs
# ---------------------------------------------------------------------------
@test "scoring: PASS threshold documented as score >= 80 AND 0 CRITICALs" {
  grep -q "PASS" "$SCORING" || fail "PASS verdict not mentioned"
  grep -q ">= 80" "$SCORING" || fail "Pass threshold >= 80 not found"
  # The PASS row should mention zero CRITICALs
  grep -q "0 CRITICAL\|no CRITICAL\|0 CRITICALs" "$SCORING" \
    || fail "PASS condition requiring 0 CRITICALs not found"
}

# ---------------------------------------------------------------------------
# 4. CONCERNS threshold: score 60-79 AND 0 CRITICALs
# ---------------------------------------------------------------------------
@test "scoring: CONCERNS threshold documented as score 60-79 AND 0 CRITICALs" {
  grep -q "CONCERNS" "$SCORING" || fail "CONCERNS verdict not mentioned"
  grep -q "60-79\|60–79" "$SCORING" || fail "CONCERNS score band 60-79 not found"
}

# ---------------------------------------------------------------------------
# 5. FAIL threshold: score < 60 OR any CRITICAL remaining
# ---------------------------------------------------------------------------
@test "scoring: FAIL threshold documented as score < 60 OR any CRITICAL" {
  grep -q "FAIL" "$SCORING" || fail "FAIL verdict not mentioned"
  grep -q "< 60\|any CRITICAL" "$SCORING" \
    || fail "FAIL condition (< 60 or any CRITICAL) not found"
}

# ---------------------------------------------------------------------------
# 6. SCOUT-* findings excluded from scoring
# ---------------------------------------------------------------------------
@test "scoring: SCOUT-* findings excluded from scoring formula" {
  grep -q "SCOUT" "$SCORING" || fail "SCOUT mention not found in scoring.md"
  grep -iq "excluded\|no point deduction\|not.*deduct\|tracked.*only" "$SCORING" \
    || fail "SCOUT findings exclusion from scoring not documented"
}

# ---------------------------------------------------------------------------
# 7. Deduplication key documented as (file, line, category)
# ---------------------------------------------------------------------------
@test "scoring: deduplication key documented as (file, line, category)" {
  grep -q "file, line, category\|file.*line.*category" "$SCORING" \
    || fail "Deduplication key (file, line, category) not found"
}

# ---------------------------------------------------------------------------
# 8. Scoring constraints documented
# ---------------------------------------------------------------------------
@test "scoring: constraints documented for critical_weight, warning_weight, info_weight, pass_threshold" {
  grep -q "critical_weight" "$SCORING"  || fail "critical_weight constraint not found"
  grep -q "warning_weight" "$SCORING"   || fail "warning_weight constraint not found"
  grep -q "info_weight" "$SCORING"      || fail "info_weight constraint not found"
  grep -q "pass_threshold" "$SCORING"   || fail "pass_threshold constraint not found"
  grep -q ">= 10" "$SCORING"            || fail "critical_weight >= 10 constraint not found"
  grep -q ">= 60" "$SCORING"            || fail "pass_threshold >= 60 constraint not found"
}

# ---------------------------------------------------------------------------
# 9. Oscillation tolerance constraint: >= 0 and <= 20
# ---------------------------------------------------------------------------
@test "scoring: oscillation_tolerance constraint is 0 to 20" {
  grep -q "oscillation_tolerance" "$SCORING" || fail "oscillation_tolerance not mentioned"
  grep -q ">= 0" "$SCORING"  || fail "oscillation_tolerance lower bound >= 0 not found"
  grep -q "<= 20" "$SCORING" || fail "oscillation_tolerance upper bound <= 20 not found"
}

# ---------------------------------------------------------------------------
# 10. Examples table: 0 CRITICAL 0 WARNING 0 INFO = 100
# ---------------------------------------------------------------------------
@test "scoring: examples table contains 0C 0W 0I = 100" {
  grep -q "0 CRITICAL, 0 WARNING, 0 INFO\|0C.*0W.*0I" "$SCORING" \
    || fail "Example row '0 CRITICAL, 0 WARNING, 0 INFO' not found"
  grep -q "| 100 |" "$SCORING" || fail "Score 100 example not found in table"
}

# ---------------------------------------------------------------------------
# 11. Category codes documented: ARCH-*, SEC-*, PERF-*, QUAL-*, CONV-*, DOC-*,
#     TEST-*, FE-PERF-*, SCOUT-*, A11Y-*, DEPS-*, COMPAT-*, REVIEW-GAP
# ---------------------------------------------------------------------------
@test "scoring: category code prefixes documented" {
  local categories=(ARCH SEC PERF QUAL CONV DOC TEST FE-PERF SCOUT A11Y DEPS COMPAT REVIEW-GAP)
  for cat in "${categories[@]}"; do
    grep -q "${cat}" "$SCORING" || fail "Category prefix ${cat} not found in scoring.md"
  done
}

# ---------------------------------------------------------------------------
# 12. Formula arithmetic verification: 100 - 20*1 - 5*2 - 2*3 = 64
# ---------------------------------------------------------------------------
@test "scoring: formula arithmetic 1C 2W 3I = 64" {
  # Compute using the documented formula
  local score
  score=$(python3 -c "print(max(0, 100 - 20*1 - 5*2 - 2*3))")
  assert_equal "$score" "64"

  # Verify the document contains an example consistent with the formula weights
  # (The doc has "1 CRITICAL, 0 WARNING, 0 INFO | 80" which means 100-20=80)
  grep -q "1 CRITICAL, 0 WARNING, 0 INFO" "$SCORING" \
    || fail "Example with 1 CRITICAL not found"
  grep -q "| 80 |" "$SCORING" \
    || fail "Score 80 for 1C 0W 0I example not found"
}
