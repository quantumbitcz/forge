#!/usr/bin/env bash
# Stop event hook: Captures session context for retrospective analysis.
# Best-effort — fails silently. Uses UTC for cross-timezone consistency.

{
  FORGE_DIR=".forge"
  [ ! -d "$FORGE_DIR" ] && exit 0
  [ ! -f "$FORGE_DIR/state.json" ] && {
    # No state — simple timestamp entry (backward compat)
    mkdir -p "$FORGE_DIR/feedback" 2>/dev/null
    printf '[%s] Session ended (no pipeline state).\n' \
      "$(date -u '+%Y-%m-%d %H:%M UTC')" >> "$FORGE_DIR/feedback/auto-captured.md"
    exit 0
  }

  mkdir -p "$FORGE_DIR/feedback" 2>/dev/null
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
except:
    print(f'[{datetime.utcnow():%Y-%m-%d %H:%M} UTC] Session ended (state unreadable).')
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

print(f'[{datetime.utcnow():%Y-%m-%d %H:%M} UTC] Session ended | '
      f'state={stage} mode={mode} score={last_score} '
      f'phase={phase} iterations={iters} retries={retries} '
      f'wall_time={wall}s')
" >> "$FORGE_DIR/feedback/auto-captured.md"
  else
    printf '[%s] Session ended.\n' "$(date -u '+%Y-%m-%d %H:%M UTC')" \
      >> "$FORGE_DIR/feedback/auto-captured.md"
  fi
} 2>/dev/null

exit 0
