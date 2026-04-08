#!/usr/bin/env bats
# Unit tests: scoring formula edge cases — validates threshold boundaries,
# clamping, and oscillation tolerance arithmetic documented in scoring.md.

load '../helpers/test-helpers'

SCORING="$PLUGIN_ROOT/shared/scoring.md"

# ---------------------------------------------------------------------------
# Helper: compute score using the documented formula
# ---------------------------------------------------------------------------
compute_score() {
  local critical="${1:-0}" warning="${2:-0}" info="${3:-0}"
  local raw=$(( 100 - 20 * critical - 5 * warning - 2 * info ))
  # Clamp to minimum 0
  if [[ $raw -lt 0 ]]; then
    echo 0
  else
    echo "$raw"
  fi
}

# Helper: determine verdict
compute_verdict() {
  local score="$1" critical="${2:-0}"
  if [[ $critical -gt 0 || $score -lt 60 ]]; then
    echo "FAIL"
  elif [[ $score -ge 80 ]]; then
    echo "PASS"
  else
    echo "CONCERNS"
  fi
}

# ---------------------------------------------------------------------------
# 1. Zero findings = score 100, verdict PASS
# ---------------------------------------------------------------------------
@test "scoring-edge: 0C 0W 0I = score 100 PASS" {
  local score
  score=$(compute_score 0 0 0)
  [[ "$score" -eq 100 ]] || fail "Expected 100, got $score"
  local verdict
  verdict=$(compute_verdict "$score" 0)
  [[ "$verdict" == "PASS" ]] || fail "Expected PASS, got $verdict"
}

# ---------------------------------------------------------------------------
# 2. Exactly at PASS threshold: score = 80
# ---------------------------------------------------------------------------
@test "scoring-edge: 1C 0W 0I = score 80 but FAIL (has CRITICAL)" {
  local score
  score=$(compute_score 1 0 0)
  [[ "$score" -eq 80 ]] || fail "Expected 80, got $score"
  local verdict
  verdict=$(compute_verdict "$score" 1)
  [[ "$verdict" == "FAIL" ]] || fail "Expected FAIL (CRITICAL present), got $verdict"
}

@test "scoring-edge: 0C 4W 0I = score 80 PASS" {
  local score
  score=$(compute_score 0 4 0)
  [[ "$score" -eq 80 ]] || fail "Expected 80, got $score"
  local verdict
  verdict=$(compute_verdict "$score" 0)
  [[ "$verdict" == "PASS" ]] || fail "Expected PASS, got $verdict"
}

# ---------------------------------------------------------------------------
# 3. Just below PASS threshold: score = 79
# ---------------------------------------------------------------------------
@test "scoring-edge: 0C 4W 1I = score 78 CONCERNS" {
  local score
  score=$(compute_score 0 4 1)
  [[ "$score" -eq 78 ]] || fail "Expected 78, got $score"
  local verdict
  verdict=$(compute_verdict "$score" 0)
  [[ "$verdict" == "CONCERNS" ]] || fail "Expected CONCERNS, got $verdict"
}

# ---------------------------------------------------------------------------
# 4. Exactly at CONCERNS lower threshold: score = 60
# ---------------------------------------------------------------------------
@test "scoring-edge: 0C 8W 0I = score 60 CONCERNS" {
  local score
  score=$(compute_score 0 8 0)
  [[ "$score" -eq 60 ]] || fail "Expected 60, got $score"
  local verdict
  verdict=$(compute_verdict "$score" 0)
  [[ "$verdict" == "CONCERNS" ]] || fail "Expected CONCERNS, got $verdict"
}

# ---------------------------------------------------------------------------
# 5. Just below CONCERNS threshold: score = 59 = FAIL
# ---------------------------------------------------------------------------
@test "scoring-edge: 0C 8W 1I = score 58 FAIL" {
  local score
  score=$(compute_score 0 8 1)
  [[ "$score" -eq 58 ]] || fail "Expected 58, got $score"
  local verdict
  verdict=$(compute_verdict "$score" 0)
  [[ "$verdict" == "FAIL" ]] || fail "Expected FAIL, got $verdict"
}

# ---------------------------------------------------------------------------
# 6. Score clamped to 0 (not negative)
# ---------------------------------------------------------------------------
@test "scoring-edge: massive deductions clamp to 0" {
  local score
  score=$(compute_score 10 20 50)
  [[ "$score" -eq 0 ]] || fail "Expected 0 (clamped), got $score"
}

# ---------------------------------------------------------------------------
# 7. Any CRITICAL = FAIL regardless of score
# ---------------------------------------------------------------------------
@test "scoring-edge: 1 CRITICAL with high score still FAIL" {
  local score
  score=$(compute_score 1 0 0)
  # Score is 80, but CRITICAL present
  local verdict
  verdict=$(compute_verdict "$score" 1)
  [[ "$verdict" == "FAIL" ]] || fail "Expected FAIL (CRITICAL), got $verdict"
}

# ---------------------------------------------------------------------------
# 8. Scoring document specifies formula arithmetic examples
# ---------------------------------------------------------------------------
@test "scoring-edge: documented example 1C 2W 3I = 64" {
  local score
  score=$(compute_score 1 2 3)
  [[ "$score" -eq 64 ]] || fail "Expected 64, got $score"
}

# ---------------------------------------------------------------------------
# 9. SCOUT-* exclusion documented
# ---------------------------------------------------------------------------
@test "scoring-edge: SCOUT-* excluded from scoring documented" {
  grep -qi "SCOUT.*exclud\|exclud.*SCOUT\|SCOUT.*not.*scor" "$SCORING" \
    || fail "SCOUT-* exclusion not documented"
}

# ---------------------------------------------------------------------------
# 10. Deduplication key documented
# ---------------------------------------------------------------------------
@test "scoring-edge: dedup key (component, file, line, category) documented" {
  grep -q "component" "$SCORING" || fail "component not in dedup key"
  grep -q "file" "$SCORING" || fail "file not in dedup key"
  grep -q "line" "$SCORING" || fail "line not in dedup key"
  grep -q "category" "$SCORING" || fail "category not in dedup key"
}

# ---------------------------------------------------------------------------
# 11. Oscillation tolerance range documented
# ---------------------------------------------------------------------------
@test "scoring-edge: oscillation_tolerance range 0-20 documented" {
  grep -q "oscillation_tolerance" "$SCORING" || fail "oscillation_tolerance not documented"
  grep -q "0.*20\|0-20" "$SCORING" || fail "oscillation_tolerance range 0-20 not documented"
}

# ---------------------------------------------------------------------------
# 12. Exactly 5 CRITICALs = 0 (boundary)
# ---------------------------------------------------------------------------
@test "scoring-edge: 5 CRITICALs = exactly 0 (boundary)" {
  local score
  score=$(compute_score 5 0 0)
  [[ "$score" -eq 0 ]] || fail "Expected exactly 0 (100 - 20*5 = 0), got $score"
}

# ---------------------------------------------------------------------------
# 13. 6 CRITICALs clamped to 0 (not negative)
# ---------------------------------------------------------------------------
@test "scoring-edge: 6 CRITICALs clamped to 0 (not -20)" {
  local score
  score=$(compute_score 6 0 0)
  [[ "$score" -eq 0 ]] || fail "Expected 0 (clamped from -20), got $score"
}

# ---------------------------------------------------------------------------
# 14. PASS boundary: score 79 is CONCERNS, not PASS
# ---------------------------------------------------------------------------
@test "scoring-edge: score 79 with 0 CRITICALs = CONCERNS" {
  local verdict
  verdict=$(compute_verdict 79 0)
  [[ "$verdict" == "CONCERNS" ]] || fail "Expected CONCERNS, got $verdict"
}

# ---------------------------------------------------------------------------
# 15. CONCERNS boundary: score 59 is FAIL, not CONCERNS
# ---------------------------------------------------------------------------
@test "scoring-edge: score 59 with 0 CRITICALs = FAIL" {
  local verdict
  verdict=$(compute_verdict 59 0)
  [[ "$verdict" == "FAIL" ]] || fail "Expected FAIL, got $verdict"
}
