#!/bin/bash
# Stop event hook: Appends a timestamped line to the feedback log when a session ends.
# Best-effort — fails silently.

{
  PIPELINE_DIR=".pipeline"
  [ ! -d "$PIPELINE_DIR" ] && exit 0

  mkdir -p "$PIPELINE_DIR/feedback" 2>/dev/null
  timestamp=$(date '+%Y-%m-%d %H:%M')
  echo "[$timestamp] Session ended. Review for feedback patterns." >> "$PIPELINE_DIR/feedback/auto-captured.md"
} 2>/dev/null

exit 0
