#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATS="$SCRIPT_DIR/lib/bats-core/bin/bats"
TIER="${1:-all}"

# Enable parallel test execution when GNU parallel is available
BATS_JOBS=()
if command -v parallel &>/dev/null; then
  NCPU=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
  BATS_JOBS=(--jobs "$NCPU" --no-parallelize-within-files)
fi

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
    run_tier "Unit Tests" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/unit/*.bats "$SCRIPT_DIR"/unit/agent-behavior/*.bats "$SCRIPT_DIR"/unit/skill-execution/*.bats
    run_tier "Hooks" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/hooks/*.bats
    run_tier "Contract Tests" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/contract/*.bats
    run_tier "Scenario Tests" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/scenario/*.bats
    run_tier "Eval Suite" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/evals/agents/*/eval.bats
    if [[ -d "$SCRIPT_DIR/evals/time-travel" ]]; then
      run_tier "Time-Travel Evals" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/evals/time-travel/*.bats
    fi
    print_summary
    ;;
  structural)
    run_tier "Structural Validation" bash "$SCRIPT_DIR/validate-plugin.sh"
    print_summary
    ;;
  unit)
    run_tier "Unit Tests" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/unit/*.bats "$SCRIPT_DIR"/unit/agent-behavior/*.bats "$SCRIPT_DIR"/unit/skill-execution/*.bats
    print_summary
    ;;
  contract)
    run_tier "Contract Tests" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/contract/*.bats
    print_summary
    ;;
  scenario)
    run_tier "Scenario Tests" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/scenario/*.bats
    print_summary
    ;;
  hooks)
    run_tier "Hooks" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/hooks/*.bats
    print_summary
    ;;
  eval|evals)
    run_tier "Eval Suite" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/evals/agents/*/eval.bats
    if [[ -d "$SCRIPT_DIR/evals/time-travel" ]]; then
      run_tier "Time-Travel Evals" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/evals/time-travel/*.bats
    fi
    print_summary
    ;;
  time-travel)
    run_tier "Time-Travel Evals" "$BATS" ${BATS_JOBS[@]+"${BATS_JOBS[@]}"} "$SCRIPT_DIR"/evals/time-travel/*.bats
    print_summary
    ;;
  pipeline-eval)
    echo "pipeline-eval tier runs only in CI (.github/workflows/evals.yml)."
    echo "Local invocation (smoke only): FORGE_EVAL=1 python -m tests.evals.pipeline.runner --dry-run --no-baseline"
    echo "To validate scenario YAML shape without running forge: python -m tests.evals.pipeline.runner --collect-only"
    exit 0
    ;;
  *)
    echo "Usage: $0 [all|structural|unit|contract|scenario|hooks|eval|time-travel|pipeline-eval]"
    exit 1
    ;;
esac

exit "$FAILURES"
