#!/usr/bin/env bash
# Validates that forge plugin prerequisites are met.
# Exit 0 if all pass, exit N where N = number of failures.
set -uo pipefail

errors=0

# Bash 4.0+ check
BASH_MAJOR="${BASH_VERSINFO[0]}"
if [[ "$BASH_MAJOR" -lt 4 ]]; then
  echo "ERROR: forge plugin requires bash 4.0+ (found ${BASH_VERSION})"
  echo "  Install with: brew install bash"
  errors=$((errors + 1))
fi

# Python 3 check
if ! command -v python3 &>/dev/null; then
  echo "ERROR: forge plugin requires python3 (not found)"
  echo "  Install with: brew install python3"
  errors=$((errors + 1))
fi

if [[ $errors -eq 0 ]]; then
  echo "OK: all prerequisites met (bash ${BASH_VERSION}, python3 $(python3 --version 2>&1 | awk '{print $2}'))"
fi

exit "$errors"
