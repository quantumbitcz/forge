#!/usr/bin/env bash
# Stop event hook: Captures session context for retrospective analysis.
# Best-effort — fails silently. Uses UTC for cross-timezone consistency.
# Uses atomic write (temp file + locked append) to prevent garbled output
# from concurrent Stop hooks (e.g., parallel sprint orchestrators).

# Self-enforcing timeout — mirrors hooks.json value
_HOOK_TIMEOUT="${FORGE_HOOK_TIMEOUT:-3}"
if [[ "${_HOOK_TIMEOUT_ACTIVE:-}" != "1" ]]; then
  export _HOOK_TIMEOUT_ACTIVE=1
  if command -v timeout &>/dev/null; then
    timeout "$_HOOK_TIMEOUT" "$0" "$@" 2>/dev/null || exit 0
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$_HOOK_TIMEOUT" "$0" "$@" 2>/dev/null || exit 0
  fi
  exit 0
fi

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

  # Atomic append: write entry to temp file, then use locking to append.
  # Prevents garbled output from concurrent Stop hooks.
  _atomic_append() {
    local entry="$1"
    local target="$2"
    local tmp_entry="${target}.$$-$(date +%s).tmp"

    # Write complete entry to temp file first
    echo "$entry" > "$tmp_entry" 2>/dev/null || {
      # Temp write failed — direct append as last resort
      echo "$entry" >> "$target" 2>/dev/null
      return
    }

    # Locked append: flock if available, else mkdir-based lock
    if command -v flock &>/dev/null; then
      (
        flock -w 2 9 || { cat "$tmp_entry" >> "$target" 2>/dev/null; rm -f "$tmp_entry"; exit 0; }
        cat "$tmp_entry" >> "$target"
        rm -f "$tmp_entry"
      ) 9>"${target}.lock"
    else
      local lock_dir="${target}.lockdir"
      if mkdir "$lock_dir" 2>/dev/null; then
        cat "$tmp_entry" >> "$target"
        rm -f "$tmp_entry"
        rmdir "$lock_dir" 2>/dev/null
      else
        # Contention fallback: direct append (best-effort)
        cat "$tmp_entry" >> "$target" 2>/dev/null
        rm -f "$tmp_entry"
      fi
    fi
  }

  _feedback_file="$FORGE_DIR/feedback/auto-captured.md"

  [ ! -f "$FORGE_DIR/state.json" ] && {
    # No state — simple timestamp entry (backward compat)
    mkdir -p "$FORGE_DIR/feedback" 2>/dev/null
    _rotate_feedback "$_feedback_file"
    _entry="$(printf '[%s] Session ended (no pipeline state).' "$(date -u '+%Y-%m-%d %H:%M UTC')")"
    _atomic_append "$_entry" "$_feedback_file"
    exit 0
  }

  mkdir -p "$FORGE_DIR/feedback" 2>/dev/null
  _rotate_feedback "$_feedback_file"
  _py=""
  command -v python3 &>/dev/null && _py="python3"
  [ -z "$_py" ] && command -v python &>/dev/null && _py="python"

  _entry=""
  if [ -n "$_py" ]; then
    _entry="$("$_py" -c "
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
")"
  else
    _entry="$(printf '[%s] Session ended.' "$(date -u '+%Y-%m-%d %H:%M UTC')")"
  fi

  # Append session entry atomically
  if [ -n "$_entry" ]; then
    _atomic_append "$_entry" "$_feedback_file"
  fi

  # Surface hook failures in session summary
  _fail_log="$FORGE_DIR/.hook-failures.log"
  if [[ -f "$_fail_log" ]]; then
    _fc=$(wc -l < "$_fail_log" 2>/dev/null | tr -d ' ')
    if [[ "$_fc" -gt 0 ]]; then
      _last_failure=$(tail -1 "$_fail_log" 2>/dev/null | head -c 200)
      _fail_entry="$(printf '  Hook failures: %s (see .forge/.hook-failures.log)' "$_fc")"
      if [[ -n "$_last_failure" ]]; then
        _fail_entry="$(printf '%s\n  Last failure: %s' "$_fail_entry" "$_last_failure")"
      fi
      _atomic_append "$_fail_entry" "$_feedback_file"
    fi
  fi
} 2>/dev/null

exit 0
