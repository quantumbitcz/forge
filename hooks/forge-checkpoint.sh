#!/usr/bin/env bash
# PostToolUse hook (Skill): Updates forge state timestamp after skill invocations.
# Best-effort — fails silently. Uses flock for atomic updates when available.

{
  STATE_FILE=".forge/state.json"
  [ ! -f "$STATE_FILE" ] && exit 0

  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  tmp=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/forge-ckpt.XXXXXX")
  trap 'rm -f "$tmp"' EXIT

  # Atomic update: flock the state file to prevent concurrent writes
  _py=""
  command -v python3 &>/dev/null && _py="python3"
  [[ -z "$_py" ]] && command -v python &>/dev/null && _py="python"

  update_state() {
    if [[ -n "$_py" ]]; then
      CKPT_STATE="$STATE_FILE" CKPT_TS="$timestamp" CKPT_TMP="$tmp" "$_py" -c "
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
    if flock -w 5 9; then
      update_state
    fi
    exec 9>&- 2>/dev/null || true
  else
    # Fallback for platforms without flock (macOS): use mkdir as atomic lock
    LOCK_DIR="${STATE_FILE}.lockdir"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      # Extend trap to clean up lock dir alongside tmp file
      trap 'rm -rf "$LOCK_DIR" "$tmp"' EXIT
      update_state
      rmdir "$LOCK_DIR" 2>/dev/null || rm -rf "$LOCK_DIR" 2>/dev/null || true
    fi
    # If lock acquisition fails, skip silently (best-effort)
  fi
} 2>/dev/null

exit 0
