#!/usr/bin/env bash
set -euo pipefail

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

run_tier() {
  local name="$1"; shift
  echo -e "\n${BOLD}=== $name ===${NC}"
  if "$@"; then
    echo -e "${GREEN}$name: PASSED${NC}"
  else
    echo -e "${RED}$name: FAILED${NC}"
    exit 1
  fi
}

case "$TIER" in
  all)
    run_tier "Structural Validation" bash "$SCRIPT_DIR/validate-plugin.sh"
    run_tier "Unit Tests" "$BATS" "$SCRIPT_DIR"/unit/*.bats
    run_tier "Contract Tests" "$BATS" "$SCRIPT_DIR"/contract/*.bats
    run_tier "Scenario Tests" "$BATS" "$SCRIPT_DIR"/scenario/*.bats
    echo -e "\n${GREEN}${BOLD}All tiers passed.${NC}"
    ;;
  structural) run_tier "Structural Validation" bash "$SCRIPT_DIR/validate-plugin.sh" ;;
  unit)       run_tier "Unit Tests" "$BATS" "$SCRIPT_DIR"/unit/*.bats ;;
  contract)   run_tier "Contract Tests" "$BATS" "$SCRIPT_DIR"/contract/*.bats ;;
  scenario)   run_tier "Scenario Tests" "$BATS" "$SCRIPT_DIR"/scenario/*.bats ;;
  *)          echo "Usage: $0 [all|structural|unit|contract|scenario]"; exit 1 ;;
esac
