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

TOKEN_FILE="${FORGE_DIR}/.token-estimate"
SUGGEST_FILE="${FORGE_DIR}/.compact-suggestion"

count=0
if [[ -f "$TOKEN_FILE" ]]; then
  count=$(cat "$TOKEN_FILE" 2>/dev/null || echo "0")
fi
count=$((count + 1))
echo "$count" > "$TOKEN_FILE"

if (( count % 5 == 0 )); then
  echo "Consider running /compact to free context space (${count} agent dispatches since last compact)" > "$SUGGEST_FILE"
fi

exit 0
