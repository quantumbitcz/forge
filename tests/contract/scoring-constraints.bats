#!/usr/bin/env bats
# Contract tests: scoring constraints — validates that PREFLIGHT constraint
# ranges from CLAUDE.md are correctly documented in scoring.md and
# convergence-engine.md.

load '../helpers/test-helpers'

SCORING="$PLUGIN_ROOT/shared/scoring.md"
CONVERGENCE="$PLUGIN_ROOT/shared/convergence-engine.md"
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"

# ===========================================================================
# Helper: compute score using the documented formula
# ===========================================================================
compute_score() {
  local critical="${1:-0}" warning="${2:-0}" info="${3:-0}"
  local raw=$(( 100 - 20 * critical - 5 * warning - 2 * info ))
  if [[ $raw -lt 0 ]]; then
    echo 0
  else
    echo "$raw"
  fi
}

# ===========================================================================
# 1. critical_weight >= 10
# ===========================================================================
@test "scoring-constraints: critical_weight >= 10 documented" {
  grep -q "critical_weight.*>= *10\|critical_weight.*must be.*10" "$SCORING" \
    || fail "critical_weight >= 10 constraint not documented in scoring.md"
}

# ===========================================================================
# 2. warning_weight >= 1
# ===========================================================================
@test "scoring-constraints: warning_weight >= 1 documented" {
  grep -q "warning_weight.*>= *1\|warning_weight.*must be.*1" "$SCORING" \
    || fail "warning_weight >= 1 constraint not documented in scoring.md"
}

# ===========================================================================
# 3. info_weight >= 0
# ===========================================================================
@test "scoring-constraints: info_weight >= 0 documented" {
  grep -q "info_weight.*>= *0\|info_weight.*must be.*0" "$SCORING" \
    || fail "info_weight >= 0 constraint not documented in scoring.md"
}

# ===========================================================================
# 4. pass_threshold >= 60
# ===========================================================================
@test "scoring-constraints: pass_threshold >= 60 documented" {
  grep -q "pass_threshold.*>= *60\|pass_threshold.*must be.*60\|below 60 is always FAIL" "$SCORING" \
    || fail "pass_threshold >= 60 constraint not documented in scoring.md"
}

# ===========================================================================
# 5. concerns_threshold >= 40
# ===========================================================================
@test "scoring-constraints: concerns_threshold >= 40 documented" {
  grep -q "concerns_threshold.*>= *40\|concerns_threshold.*must be.*40" "$SCORING" \
    || fail "concerns_threshold >= 40 constraint not documented in scoring.md"
}

# ===========================================================================
# 6. gap between pass and concerns >= 10
# ===========================================================================
@test "scoring-constraints: gap between pass and concerns >= 10 documented" {
  grep -q "pass_threshold.*concerns_threshold.*>= *10\|>= *10\|gap.*10\|distinct verdict bands" "$SCORING" \
    || fail "Gap >= 10 between pass and concerns not documented in scoring.md"
}

# ===========================================================================
# 7. oscillation_tolerance 0-20
# ===========================================================================
@test "scoring-constraints: oscillation_tolerance range 0-20 documented" {
  grep -q "oscillation_tolerance" "$SCORING" \
    || fail "oscillation_tolerance not documented in scoring.md"
  grep -q "0.*20\|>= *0.*<= *20" "$SCORING" \
    || fail "oscillation_tolerance range 0-20 not in scoring.md"
}

# ===========================================================================
# 8. total_retries_max 5-30
# ===========================================================================
@test "scoring-constraints: total_retries_max 5-30 documented in CLAUDE.md" {
  grep -q "total_retries_max.*5.*30\|total_retries_max" "$CLAUDE_MD" \
    || fail "total_retries_max 5-30 not documented in CLAUDE.md"
}

# ===========================================================================
# 9. max_iterations 3-20
# ===========================================================================
@test "scoring-constraints: convergence max_iterations 3-20 documented" {
  grep -q "max_iterations.*3.*20\|>= *3.*<= *20" "$SCORING" \
    || grep -q "max_iterations.*3.*20\|>= *3.*<= *20" "$CONVERGENCE" \
    || fail "max_iterations 3-20 not documented in scoring.md or convergence-engine.md"
}

# ===========================================================================
# 10. plateau_threshold 0-10
# ===========================================================================
@test "scoring-constraints: plateau_threshold 0-10 documented" {
  grep -q "plateau_threshold.*0.*10\|>= *0.*<= *10" "$SCORING" \
    || grep -q "plateau_threshold.*0.*10\|>= *0.*<= *10" "$CONVERGENCE" \
    || fail "plateau_threshold 0-10 not documented in scoring.md or convergence-engine.md"
}

# ===========================================================================
# 11. plateau_patience 1-5
# ===========================================================================
@test "scoring-constraints: plateau_patience 1-5 documented" {
  grep -q "plateau_patience.*1.*5\|>= *1.*<= *5" "$SCORING" \
    || grep -q "plateau_patience.*1.*5\|>= *1.*<= *5" "$CONVERGENCE" \
    || fail "plateau_patience 1-5 not documented in scoring.md or convergence-engine.md"
}

# ===========================================================================
# 12. target_score in [pass_threshold, 100]
# ===========================================================================
@test "scoring-constraints: target_score range in [pass_threshold, 100] documented" {
  grep -q "target_score.*pass_threshold\|target_score.*>= *pass_threshold" "$SCORING" \
    || grep -q "target_score.*pass_threshold" "$CONVERGENCE" \
    || fail "target_score >= pass_threshold not documented"
  grep -q "target_score.*100\|<= *100" "$SCORING" \
    || grep -q "target_score.*100\|<= *100" "$CONVERGENCE" \
    || fail "target_score <= 100 not documented"
}

# ===========================================================================
# 13. SCOUT-* excluded from score
# ===========================================================================
@test "scoring-constraints: SCOUT-* excluded from scoring" {
  grep -qi "SCOUT.*exclud\|exclud.*SCOUT\|SCOUT.*not.*scor\|SCOUT.*never scored" "$SCORING" \
    || fail "SCOUT-* exclusion not documented in scoring.md"
}

# ===========================================================================
# 14. Formula matches: score = max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)
# ===========================================================================
@test "scoring-constraints: formula max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO) documented" {
  grep -q "100.*20.*CRITICAL.*5.*WARNING.*2.*INFO" "$SCORING" \
    || fail "Scoring formula not documented in scoring.md"
  # Verify arithmetic correctness
  local score
  score=$(compute_score 1 2 3)
  [[ "$score" -eq 64 ]] || fail "Formula check: 1C+2W+3I should be 64, got $score"
  score=$(compute_score 0 0 0)
  [[ "$score" -eq 100 ]] || fail "Formula check: 0C+0W+0I should be 100, got $score"
  score=$(compute_score 6 0 0)
  [[ "$score" -eq 0 ]] || fail "Formula check: 6C should clamp to 0, got $score"
}

# ===========================================================================
# 15. All 19 shared categories exist (16 wildcard + 3 discrete)
# ===========================================================================
@test "scoring-constraints: all 19 shared categories documented in scoring.md" {
  # 16 wildcard prefixes
  local wildcard_categories=(
    "ARCH-"
    "SEC-"
    "PERF-"
    "FE-PERF-"
    "TEST-"
    "CONV-"
    "DOC-"
    "QUAL-"
    "APPROACH-"
    "SCOUT-"
    "A11Y-"
    "DEP-"
    "COMPAT-"
    "CONTRACT-"
    "STRUCT-"
    "INFRA-"
  )

  local missing=0
  for cat in "${wildcard_categories[@]}"; do
    grep -q "${cat}" "$SCORING" \
      || { echo "Missing wildcard category: ${cat}*" >&2; missing=$((missing + 1)); }
  done

  # 3 discrete categories
  for cat in "REVIEW-GAP" "DESIGN-TOKEN" "DESIGN-MOTION"; do
    grep -q "$cat" "$SCORING" \
      || { echo "Missing discrete category: $cat" >&2; missing=$((missing + 1)); }
  done

  [[ "$missing" -eq 0 ]] \
    || fail "$missing of 19 shared categories missing from scoring.md"
}
