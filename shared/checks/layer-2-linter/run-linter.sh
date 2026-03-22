#!/usr/bin/env bash
set -euo pipefail

# Layer 2 linter bridge dispatcher.
# Detects the appropriate linter for a language, runs its adapter,
# and emits unified findings to stdout.
#
# Usage: run-linter.sh <language> <project-root> <file-or-dir> <severity-map>
# Exit:  always 0

trap 'exit 0' ERR

LANGUAGE="${1:-}"
PROJECT_ROOT="${2:-}"
TARGET="${3:-}"
SEVERITY_MAP="${4:-}"

[[ -z "$LANGUAGE" || -z "$TARGET" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTER_DIR="$SCRIPT_DIR/adapters"

# Map language → primary linter, fallback linter
declare -A PRIMARY FALLBACK
PRIMARY=(
  [kotlin]=detekt      [java]=checkstyle   [typescript]=eslint
  [python]=ruff        [go]=staticcheck    [rust]=clippy
  [c]=clang-tidy       [swift]=swiftlint
)
FALLBACK=(
  [kotlin]=ktlint      [java]=spotbugs     [typescript]=biome
  [python]=pylint      [go]="go"           [c]=cppcheck
)

# Resolve the linter binary name for command -v checks
resolve_bin() {
  case "$1" in
    clippy) echo "cargo" ;;
    *)      echo "$1" ;;
  esac
}

# Try primary, then fallback; run the matching adapter
run_adapter() {
  local linter="$1"
  local adapter="$ADAPTER_DIR/${linter}.sh"
  [[ ! -x "$adapter" ]] && return 1

  "$adapter" "$PROJECT_ROOT" "$TARGET" "$SEVERITY_MAP"
}

primary="${PRIMARY[$LANGUAGE]:-}"
fallback="${FALLBACK[$LANGUAGE]:-}"

if [[ -n "$primary" ]] && command -v "$(resolve_bin "$primary")" &>/dev/null; then
  run_adapter "$primary" && exit 0
fi

if [[ -n "$fallback" ]] && command -v "$(resolve_bin "$fallback")" &>/dev/null; then
  run_adapter "$fallback" && exit 0
fi

echo "INFO: No linter available for $LANGUAGE, using pattern-based checks only" >&2
exit 0
