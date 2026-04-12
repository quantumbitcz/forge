#!/usr/bin/env bats
# Unit test: scoring formula and verdict determination.
# Formula: max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)
# Verdicts: PASS >= 80 (and 0 unresolved CRITICAL), CONCERNS 60-79, FAIL < 60 or unresolved CRITICAL

load '../helpers/test-helpers'

# Implement the scoring formula in bash (specification test)
compute_score() {
  local critical="${1:-0}" warning="${2:-0}" info="${3:-0}"
  local raw=$((100 - 20 * critical - 5 * warning - 2 * info))
  if (( raw < 0 )); then
    echo 0
  else
    echo "$raw"
  fi
}

# Determine verdict
compute_verdict() {
  local score="$1" unresolved_critical="${2:-0}"
  if (( unresolved_critical > 0 )); then
    echo "FAIL"
  elif (( score >= 80 )); then
    echo "PASS"
  elif (( score >= 60 )); then
    echo "CONCERNS"
  else
    echo "FAIL"
  fi
}

@test "scoring: clean slate = 100" {
  local score
  score="$(compute_score 0 0 0)"
  [[ "$score" == "100" ]]
}

@test "scoring: 1 critical = 80" {
  local score
  score="$(compute_score 1 0 0)"
  [[ "$score" == "80" ]]
}

@test "scoring: 5 criticals floors at 0" {
  local score
  score="$(compute_score 5 0 0)"
  [[ "$score" == "0" ]]
}

@test "scoring: 6 criticals still floors at 0 (max function)" {
  local score
  score="$(compute_score 6 0 0)"
  [[ "$score" == "0" ]]
}

@test "scoring: mixed findings (1C + 2W + 3I = 64)" {
  local score
  score="$(compute_score 1 2 3)"
  [[ "$score" == "64" ]]
}

@test "scoring: verdict PASS when score >= 80 and 0 critical" {
  local verdict
  verdict="$(compute_verdict 80 0)"
  [[ "$verdict" == "PASS" ]]
}

@test "scoring: verdict CONCERNS when 60 <= score < 80" {
  local verdict
  verdict="$(compute_verdict 70 0)"
  [[ "$verdict" == "CONCERNS" ]]
}

@test "scoring: verdict FAIL when score < 60" {
  local verdict
  verdict="$(compute_verdict 45 0)"
  [[ "$verdict" == "FAIL" ]]
}

@test "scoring: verdict FAIL when unresolved CRITICAL regardless of score" {
  local verdict
  verdict="$(compute_verdict 80 1)"
  [[ "$verdict" == "FAIL" ]]
}

@test "scoring: deduplication — same key counted once" {
  # Simulate: two findings with identical (component, file, line, category)
  # Only one should contribute to score
  local findings=(
    "comp1|src/main.ts|42|SEC-001"
    "comp1|src/main.ts|42|SEC-001"
    "comp1|src/main.ts|99|QUAL-001"
  )
  # Deduplicate by unique key
  local unique_count
  unique_count="$(printf '%s\n' "${findings[@]}" | sort -u | wc -l | tr -d ' ')"
  [[ "$unique_count" == "2" ]]
}
