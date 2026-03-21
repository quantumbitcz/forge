#!/bin/bash
# PostToolUse hook (Skill): Updates pipeline state timestamp after skill invocations.
# Best-effort — fails silently.

{
  STATE_FILE=".pipeline/state.json"
  [ ! -f "$STATE_FILE" ] && exit 0

  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  tmp=$(mktemp)
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
with open('$STATE_FILE') as f:
    data = json.load(f)
data['lastCheckpoint'] = '$timestamp'
with open('$tmp', 'w') as f:
    json.dump(data, f, indent=2)
" && mv "$tmp" "$STATE_FILE"
  else
    # Fallback: simple sed replacement
    sed "s/\"lastCheckpoint\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"lastCheckpoint\": \"$timestamp\"/" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  fi
} 2>/dev/null

exit 0
