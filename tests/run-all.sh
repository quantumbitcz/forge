#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS="$SCRIPT_DIR/lib/bats-core/bin/bats"
TIER="${1:-all}"

# Verify bats is available (except for structural-only runs which don't need it)
if [[ "$TIER" != "structural" ]] && [[ ! -x "$BATS" ]]; then
  echo "ERROR: bats not found at $BATS" >&2
  echo "  Run: git submodule update --init --recursive" >&2
  exit 1
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'

# Track results across all suites
RESULTS=()
FAILURES=0
TOTAL_START=$(date +%s)

run_tier() {
  local name="$1"; shift
  local start_time end_time duration
  start_time=$(date +%s)
  printf '\n%b=== %s ===%b\n' "$BOLD" "$name" "$NC"
  if "$@"; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    printf '%b%s: PASSED (%ds)%b\n' "$GREEN" "$name" "$duration" "$NC"
    RESULTS+=("PASS|$name|${duration}s")
  else
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    printf '%b%s: FAILED (%ds)%b\n' "$RED" "$name" "$duration" "$NC"
    RESULTS+=("FAIL|$name|${duration}s")
    FAILURES=$((FAILURES + 1))
  fi
}

print_summary() {
  local total_end
  total_end=$(date +%s)
  local total_elapsed=$((total_end - TOTAL_START))

  printf '\n%b=== Summary ===%b\n' "$BOLD" "$NC"
  printf '%-12s %-35s %s\n' "Result" "Suite" "Duration"
  printf '%-12s %-35s %s\n' "------" "-----" "--------"
  for result in "${RESULTS[@]}"; do
    IFS='|' read -r status suite duration <<< "$result"
    if [[ "$status" == "PASS" ]]; then
      printf '%b%-12s%b %-35s %s\n' "$GREEN" "$status" "$NC" "$suite" "$duration"
    else
      printf '%b%-12s%b %-35s %s\n' "$RED" "$status" "$NC" "$suite" "$duration"
    fi
  done

  local passed=$((${#RESULTS[@]} - FAILURES))
  printf '\n%bTotal: %d passed, %d failed (%.0fs)%b\n' \
    "$BOLD" "$passed" "$FAILURES" "$total_elapsed" "$NC"

  if [[ $FAILURES -eq 0 ]]; then
    printf '%bAll tiers passed.%b\n' "${GREEN}${BOLD}" "$NC"
  else
    printf '%b%d suite(s) failed.%b\n' "${RED}${BOLD}" "$FAILURES" "$NC"
  fi
}

case "$TIER" in
  all)
    run_tier "Structural Validation" bash "$SCRIPT_DIR/validate-plugin.sh"
    run_tier "Unit Tests" "$BATS" "$SCRIPT_DIR"/unit/*.bats "$SCRIPT_DIR"/unit/agent-behavior/*.bats "$SCRIPT_DIR"/unit/skill-execution/*.bats
    run_tier "Hooks" "$BATS" "$SCRIPT_DIR"/hooks/*.bats
    run_tier "Contract Tests" "$BATS" "$SCRIPT_DIR"/contract/*.bats
    run_tier "Scenario Tests" "$BATS" "$SCRIPT_DIR"/scenario/*.bats
    run_tier "Eval Suite" "$BATS" "$SCRIPT_DIR"/evals/agents/*/eval.bats
    print_summary
    ;;
  structural)
    run_tier "Structural Validation" bash "$SCRIPT_DIR/validate-plugin.sh"
    print_summary
    ;;
  unit)
    run_tier "Unit Tests" "$BATS" "$SCRIPT_DIR"/unit/*.bats "$SCRIPT_DIR"/unit/agent-behavior/*.bats "$SCRIPT_DIR"/unit/skill-execution/*.bats
    print_summary
    ;;
  contract)
    run_tier "Contract Tests" "$BATS" "$SCRIPT_DIR"/contract/*.bats
    print_summary
    ;;
  scenario)
    run_tier "Scenario Tests" "$BATS" "$SCRIPT_DIR"/scenario/*.bats
    print_summary
    ;;
  hooks)
    run_tier "Hooks" "$BATS" "$SCRIPT_DIR"/hooks/*.bats
    print_summary
    ;;
  eval|evals)
    run_tier "Eval Suite" "$BATS" "$SCRIPT_DIR"/evals/agents/*/eval.bats
    print_summary
    ;;
  *)
    echo "Usage: $0 [all|structural|unit|contract|scenario|hooks|eval]"
    exit 1
    ;;
esac

exit "$FAILURES"
