#!/usr/bin/env bash
# PostToolUse hook (Skill): Updates forge state timestamp after skill invocations.
# Best-effort — logs failures to .hook-failures.log. Uses atomic_json_update from platform.sh.

# Self-enforcing timeout — mirrors hooks.json value
_HOOK_TIMEOUT="${FORGE_HOOK_TIMEOUT:-5}"
if [[ "${_HOOK_TIMEOUT_ACTIVE:-}" != "1" ]]; then
  export _HOOK_TIMEOUT_ACTIVE=1
  if command -v timeout &>/dev/null; then
    timeout "$_HOOK_TIMEOUT" "$0" "$@" || true
    exit 0
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$_HOOK_TIMEOUT" "$0" "$@" || true
    exit 0
  fi
  # Fallback: background watchdog kill
  _SELF_PID=$$
  ( sleep "$_HOOK_TIMEOUT" && kill -TERM "$_SELF_PID" 2>/dev/null ) &
  _WATCHDOG_PID=$!
  trap "kill '$_WATCHDOG_PID' 2>/dev/null" EXIT
fi

STATE_FILE=".forge/state.json"
[ ! -f "$STATE_FILE" ] && exit 0

# Resolve plugin root from hook location
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${PLUGIN_ROOT}/shared/platform.sh" 2>/dev/null || exit 0

# Verify atomic_json_update was loaded before calling
type atomic_json_update &>/dev/null || exit 0

# Validate state.json is valid JSON before updating
"${FORGE_PYTHON:-python3}" -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null || {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | forge-checkpoint | invalid_json | $STATE_FILE" \
    >> ".forge/.hook-failures.log" 2>/dev/null
  exit 0
}

timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
atomic_json_update "$STATE_FILE" "data['lastCheckpoint'] = '$timestamp'" 2>/dev/null || {
  # Log failure instead of silently swallowing
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | forge-checkpoint | update_failed | $STATE_FILE" \
    >> ".forge/.hook-failures.log" 2>/dev/null
}

# Rotate hook failures log if too large
_hook_log="${FORGE_DIR:-.forge}/.hook-failures.log"
if [[ -f "$_hook_log" ]]; then
  _size=$(wc -c < "$_hook_log" 2>/dev/null || echo 0)
  if [[ "$_size" -gt 102400 ]]; then
    tail -1000 "$_hook_log" > "${_hook_log}.tmp" 2>/dev/null && \
      mv "${_hook_log}.tmp" "$_hook_log" 2>/dev/null || \
      rm -f "${_hook_log}.tmp" 2>/dev/null
  fi
fi

exit 0
