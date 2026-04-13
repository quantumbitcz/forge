#!/usr/bin/env bash
# PostToolUse hook (Skill): Updates forge state timestamp after skill invocations.
# Best-effort — logs failures to .hook-failures.log. Uses atomic_json_update from platform.sh.

# Self-enforcing timeout — mirrors hooks.json value
_HOOK_TIMEOUT="${FORGE_HOOK_TIMEOUT:-5}"
if [[ "${_HOOK_TIMEOUT_ACTIVE:-}" != "1" ]]; then
  export _HOOK_TIMEOUT_ACTIVE=1
  if command -v timeout &>/dev/null; then
    timeout "$_HOOK_TIMEOUT" "$0" "$@" || exit 0
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$_HOOK_TIMEOUT" "$0" "$@" || exit 0
  fi
  # No timeout command available — continue without enforcement
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

exit 0
