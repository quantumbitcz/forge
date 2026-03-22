#!/usr/bin/env bash
# pre-stage-health.sh — Checks required dependencies for a given pipeline stage.
# Usage: pre-stage-health.sh <stage_name>
# Output: "OK" if all required deps available, or "MISSING: dep1, dep2"
# Exit: always 0

set -euo pipefail

STAGE="${1:-}"

if [[ -z "$STAGE" ]]; then
  echo "MISSING: stage argument (usage: pre-stage-health.sh <stage_name>)"
  exit 0
fi

# Normalize to lowercase
STAGE="$(echo "$STAGE" | tr '[:upper:]' '[:lower:]')"

missing=()

# Check if a command exists
check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    missing+=("$1")
  fi
}

# Detect build tool from project files
detect_build_tool() {
  if [[ -f "./gradlew" ]]; then
    if [[ ! -x "./gradlew" ]]; then
      missing+=("gradlew (exists but not executable)")
    fi
  elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
    check_cmd "gradle"
  elif [[ -f "package.json" ]]; then
    if command -v pnpm &>/dev/null; then
      : # pnpm available
    elif command -v npm &>/dev/null; then
      : # npm available
    else
      missing+=("npm or pnpm")
    fi
  fi
}

# Detect test runner (same as build tool for most projects)
detect_test_tool() {
  detect_build_tool
}

case "$STAGE" in
  preflight)
    check_cmd "git"
    check_cmd "python3"
    ;;
  explore|plan|validate|review|docs|learn)
    # No required external deps beyond the agent runtime
    ;;
  implement)
    check_cmd "git"
    detect_build_tool
    ;;
  verify)
    detect_build_tool
    detect_test_tool
    ;;
  ship)
    check_cmd "git"
    # gh is optional — check but don't fail
    if ! command -v gh &>/dev/null; then
      echo "OK (note: gh CLI not found — PR creation will be skipped)"
      exit 0
    fi
    ;;
  preview)
    # Network connectivity check
    if ! curl -s --max-time 5 https://api.github.com >/dev/null 2>&1; then
      missing+=("network connectivity")
    fi
    # Playwright is optional
    if ! command -v npx &>/dev/null; then
      echo "OK (note: npx not found — playwright checks will be skipped)"
      exit 0
    fi
    ;;
  *)
    echo "OK (unknown stage: $STAGE — no checks defined)"
    exit 0
    ;;
esac

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "OK"
else
  # Join array with comma+space
  result=""
  for dep in "${missing[@]}"; do
    if [[ -n "$result" ]]; then
      result="$result, $dep"
    else
      result="$dep"
    fi
  done
  echo "MISSING: $result"
fi

exit 0
