#!/usr/bin/env bash
# PostToolUse hook (Skill): Updates forge state timestamp after skill invocations.
# Best-effort — fails silently. Uses atomic_json_update from platform.sh.

{
  STATE_FILE=".forge/state.json"
  [ ! -f "$STATE_FILE" ] && exit 0

  # Resolve plugin root from hook location
  PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  source "${PLUGIN_ROOT}/shared/platform.sh" 2>/dev/null || {
    # Fallback: if platform.sh fails to load, skip silently
    exit 0
  }

  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  atomic_json_update "$STATE_FILE" "data['lastCheckpoint'] = '$timestamp'" 2>/dev/null
} 2>/dev/null

exit 0
