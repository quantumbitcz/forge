#!/usr/bin/env bash
# After every Agent dispatch, check if compaction is needed.
# Writes suggestion to .forge/.compact-suggestion (file-based, not stdout).
set -uo pipefail

# Self-enforcing timeout — mirrors hooks.json value
_HOOK_TIMEOUT="${FORGE_HOOK_TIMEOUT:-3}"
if [[ "${_HOOK_TIMEOUT_ACTIVE:-}" != "1" ]]; then
  export _HOOK_TIMEOUT_ACTIVE=1
  if command -v timeout &>/dev/null; then
    timeout "$_HOOK_TIMEOUT" "$0" "$@" || true
    exit 0
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$_HOOK_TIMEOUT" "$0" "$@" || true
    exit 0
  fi
  # No timeout command available — continue without enforcement
fi

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
  count=$(atomic_increment "$TOKEN_FILE") || count=""
else
  # Fallback with inline flock if available
  if command -v flock &>/dev/null; then
    count=$(
      flock -w 2 9 || { echo ""; exit 1; }
      c=0
      [ -f "$TOKEN_FILE" ] && c=$(cat "$TOKEN_FILE" 2>/dev/null || echo 0)
      [[ "$c" =~ ^[0-9]+$ ]] || c=0
      c=$((c + 1))
      echo "$c" > "$TOKEN_FILE"
      echo "$c"
    ) 9>"${TOKEN_FILE}.lock" || count=""
  else
    lock="${TOKEN_FILE}.lockdir"
    max_wait=10
    i=0
    while ! mkdir "$lock" 2>/dev/null; do
      i=$((i + 1))
      if [[ $i -ge $max_wait ]]; then
        rmdir "$lock" 2>/dev/null || rm -rf "$lock" 2>/dev/null
        mkdir "$lock" 2>/dev/null || { count=""; break; }
        break
      fi
      sleep 0.1
    done
    if [[ -d "$lock" ]]; then
      count=0
      [[ -f "$TOKEN_FILE" ]] && count=$(cat "$TOKEN_FILE" 2>/dev/null || echo 0)
      [[ "$count" =~ ^[0-9]+$ ]] || count=0
      count=$((count + 1))
      echo "$count" > "$TOKEN_FILE" 2>/dev/null || true
      rmdir "$lock" 2>/dev/null
    fi
  fi
fi

# Log failure if increment failed or returned empty
if [[ -z "$count" ]]; then
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) compact-check: atomic_increment failed or returned empty" \
    >> "${FORGE_DIR}/forge.log" 2>/dev/null
  # Rotate forge.log if too large (>100KB)
  _log_file="${FORGE_DIR}/forge.log"
  if [[ -f "$_log_file" ]]; then
    _lsize=$(wc -c < "$_log_file" 2>/dev/null || echo 0)
    if [[ "$_lsize" -gt 102400 ]]; then
      tail -1000 "$_log_file" > "${_log_file}.tmp" 2>/dev/null && \
        mv "${_log_file}.tmp" "$_log_file" 2>/dev/null || \
        rm -f "${_log_file}.tmp" 2>/dev/null
    fi
  fi
  count=0
fi

if (( count % 5 == 0 )); then
  echo "Consider running /compact to free context space (${count} agent dispatches since last compact)" > "$SUGGEST_FILE"
fi

exit 0
