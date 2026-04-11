#!/usr/bin/env bash
# After every Agent dispatch, check if compaction is needed.
# Writes suggestion to .forge/.compact-suggestion (file-based, not stdout).
set -uo pipefail

FORGE_DIR="${FORGE_DIR:-.forge}"

# Parse --forge-dir if provided
while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir) shift; FORGE_DIR="${1:?--forge-dir requires path}"; shift ;;
    *) shift ;;
  esac
done

[[ -d "$FORGE_DIR" ]] || exit 0

# Source platform.sh for atomic_increment
source "$(dirname "${BASH_SOURCE[0]}")/platform.sh" 2>/dev/null

TOKEN_FILE="${FORGE_DIR}/.token-estimate"
SUGGEST_FILE="${FORGE_DIR}/.compact-suggestion"

if type atomic_increment &>/dev/null; then
  count=$(atomic_increment "$TOKEN_FILE")
else
  # Fallback with inline flock if available
  if command -v flock &>/dev/null; then
    count=$(
      flock -w 2 9 || { echo "0"; exit 1; }
      c=0
      [ -f "$TOKEN_FILE" ] && c=$(cat "$TOKEN_FILE" 2>/dev/null || echo 0)
      [[ "$c" =~ ^[0-9]+$ ]] || c=0
      c=$((c + 1))
      echo "$c" > "$TOKEN_FILE"
      echo "$c"
    ) 9>"${TOKEN_FILE}.lock" || count=0
  else
    # Last resort: accept possible race on systems without flock
    count=0
    [[ -f "$TOKEN_FILE" ]] && count=$(cat "$TOKEN_FILE" 2>/dev/null || echo "0")
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    count=$((count + 1))
    echo "$count" > "$TOKEN_FILE"
  fi
fi

if (( count % 5 == 0 )); then
  echo "Consider running /compact to free context space (${count} agent dispatches since last compact)" > "$SUGGEST_FILE"
fi

exit 0
