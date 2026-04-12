#!/usr/bin/env bash
# Stop event hook: Captures session context for retrospective analysis.
# Best-effort — fails silently. Uses UTC for cross-timezone consistency.

{
  FORGE_DIR=".forge"
  [ ! -d "$FORGE_DIR" ] && exit 0

  # Rotate auto-captured.md when it exceeds 100KB to prevent unbounded growth
  _rotate_feedback() {
    local target="$1"
    if [ -f "$target" ]; then
      local size=0
      if command -v stat &>/dev/null; then
        # GNU stat vs BSD stat (macOS)
        size=$(stat -f%z "$target" 2>/dev/null || stat -c%s "$target" 2>/dev/null || echo 0)
      fi
      if [ "$size" -gt 102400 ] 2>/dev/null; then
        local archive_name
        archive_name="$FORGE_DIR/feedback/auto-captured-$(date -u '+%Y%m%d-%H%M%S').md"
        mv "$target" "$archive_name" 2>/dev/null || true
      fi
    fi
  }

  [ ! -f "$FORGE_DIR/state.json" ] && {
    # No state — simple timestamp entry (backward compat)
    mkdir -p "$FORGE_DIR/feedback" 2>/dev/null
    _rotate_feedback "$FORGE_DIR/feedback/auto-captured.md"
    printf '[%s] Session ended (no pipeline state).\n' \
      "$(date -u '+%Y-%m-%d %H:%M UTC')" >> "$FORGE_DIR/feedback/auto-captured.md"
    exit 0
  }

  mkdir -p "$FORGE_DIR/feedback" 2>/dev/null
  _rotate_feedback "$FORGE_DIR/feedback/auto-captured.md"
  _py=""
  command -v python3 &>/dev/null && _py="python3"
  [ -z "$_py" ] && command -v python &>/dev/null && _py="python"

  if [ -n "$_py" ]; then
    "$_py" -c "
import json, sys, os
from datetime import datetime

state_file = os.path.join('$FORGE_DIR', 'state.json')
try:
    with open(state_file) as f:
        s = json.load(f)
except (IOError, json.JSONDecodeError, ValueError, KeyError) as e:
    ts = datetime.utcnow().strftime('%Y-%m-%d %H:%M')
    print('[{0} UTC] Session ended (state error: {1}).'.format(ts, type(e).__name__))
    sys.exit(0)

stage = s.get('story_state', 'UNKNOWN')
mode = s.get('mode', 'standard')
scores = s.get('score_history', [])
last_score = scores[-1] if scores else 'N/A'
conv = s.get('convergence', {})
phase = conv.get('phase', 'N/A')
iters = conv.get('total_iterations', 0)
retries = s.get('total_retries', 0)
wall = s.get('cost', {}).get('wall_time_seconds', 0)

ts = datetime.utcnow().strftime('%Y-%m-%d %H:%M')
print('[{0} UTC] Session ended | state={1} mode={2} score={3} phase={4} iterations={5} retries={6} wall_time={7}s'.format(
    ts, stage, mode, last_score, phase, iters, retries, wall))
" >> "$FORGE_DIR/feedback/auto-captured.md"
  else
    printf '[%s] Session ended.\n' "$(date -u '+%Y-%m-%d %H:%M UTC')" \
      >> "$FORGE_DIR/feedback/auto-captured.md"
  fi
  # Surface hook failures in session summary
  _fail_log="$FORGE_DIR/.hook-failures.log"
  if [[ -f "$_fail_log" ]]; then
    _fc=$(wc -l < "$_fail_log" 2>/dev/null | tr -d ' ')
    if [[ "$_fc" -gt 0 ]]; then
      printf '  Hook failures: %s (see .forge/.hook-failures.log)\n' "$_fc" \
        >> "$FORGE_DIR/feedback/auto-captured.md" 2>/dev/null
    fi
  fi
} 2>/dev/null

exit 0
