#!/usr/bin/env bash
# Stop event hook: Appends a timestamped line to the feedback log when a session ends.
# Best-effort — fails silently. Uses UTC for cross-timezone consistency.

{
  PIPELINE_DIR=".pipeline"
  [ ! -d "$PIPELINE_DIR" ] && exit 0

  mkdir -p "$PIPELINE_DIR/feedback" 2>/dev/null
  timestamp=$(date -u '+%Y-%m-%d %H:%M UTC')

  # Write to temp first to avoid partial line appends from concurrent sessions
  tmp=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/pipeline-fb.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  printf '[%s] Session ended. Review for feedback patterns.\n' "$timestamp" > "$tmp"
  cat "$tmp" >> "$PIPELINE_DIR/feedback/auto-captured.md"
} 2>/dev/null

exit 0
