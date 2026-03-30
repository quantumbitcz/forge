#!/usr/bin/env bash
# PostToolUse hook (Skill): Updates pipeline state timestamp after skill invocations.
# Best-effort — fails silently. Uses flock for atomic updates when available.

{
  STATE_FILE=".pipeline/state.json"
  [ ! -f "$STATE_FILE" ] && exit 0

  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  tmp=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/pipeline-ckpt.XXXXXX")
  trap 'rm -f "$tmp"' EXIT

  # Atomic update: flock the state file to prevent concurrent writes
  update_state() {
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
  }

  if command -v flock &>/dev/null; then
    exec 9>"${STATE_FILE}.lock"
    flock -w 5 9 && update_state
    exec 9>&-
  else
    # Fallback for platforms without flock (macOS): use mkdir as atomic lock
    LOCK_DIR="${STATE_FILE}.lockdir"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      trap 'rm -rf "$LOCK_DIR" "$tmp"' EXIT
      update_state
      rmdir "$LOCK_DIR" 2>/dev/null
    fi
    # If lock acquisition fails, skip silently (best-effort)
  fi
} 2>/dev/null

exit 0
