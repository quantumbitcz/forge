#!/usr/bin/env bash
# PostToolUse hook (Skill): Updates pipeline state timestamp after skill invocations.
# Best-effort — fails silently.

{
  STATE_FILE=".pipeline/state.json"
  [ ! -f "$STATE_FILE" ] && exit 0

  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  tmp=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/pipeline-ckpt.XXXXXX")
  if command -v python3 &>/dev/null; then
    CKPT_STATE="$STATE_FILE" CKPT_TS="$timestamp" CKPT_TMP="$tmp" python3 -c "
import json, os
state_file = os.environ['CKPT_STATE']
with open(state_file) as f:
    data = json.load(f)
data['lastCheckpoint'] = os.environ['CKPT_TS']
with open(os.environ['CKPT_TMP'], 'w') as f:
    json.dump(data, f, indent=2)
" && mv "$tmp" "$STATE_FILE"
  else
    # Fallback: simple sed replacement
    # $timestamp is safe: produced by date with fixed format (digits, hyphens, colons, T, Z only)
    sed "s/\"lastCheckpoint\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"lastCheckpoint\": \"$timestamp\"/" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  fi
} 2>/dev/null

exit 0
