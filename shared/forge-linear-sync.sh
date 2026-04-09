#!/usr/bin/env bash
# Event-driven Linear sync — centralises the "check availability → log → handle" pattern.
# Usage:
#   forge-linear-sync.sh emit <event-type> <event-json> [--forge-dir PATH]
#
# NEVER returns non-zero. NEVER blocks the pipeline.
# Always appends to .forge/linear-events.jsonl (audit trail).
# Truncates log at 100 entries.

set -uo pipefail

FORGE_DIR=".forge"
CMD=""
EVENT_TYPE=""
EVENT_JSON=""
LOG_MAX=100

# ── Argument parsing ──────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    emit)
      CMD="emit"
      shift
      EVENT_TYPE="${1:-}"
      shift || true
      EVENT_JSON="${1:-}"
      shift || true
      ;;
    --forge-dir) shift; FORGE_DIR="${1:?--forge-dir requires a path}"; shift ;;
    *) shift ;;  # ignore unknown args — never fail
  esac
done

if [[ -z "$CMD" ]]; then
  echo "Usage: forge-linear-sync.sh emit <event-type> <event-json> [--forge-dir <path>]" >&2
  exit 0  # never non-zero
fi

STATE_WRITER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/forge-state-write.sh"
LOG_FILE="${FORGE_DIR}/linear-events.jsonl"

# ── Helpers ───────────────────────────────────────────────────────────────

# Read Linear availability from state.json. Returns "true", "false", or "false" on any error.
_linear_available() {
  if [[ ! -f "${FORGE_DIR}/state.json" ]]; then
    echo "false"
    return 0
  fi
  python3 -c "
import json, sys
try:
    with open('${FORGE_DIR}/state.json') as f:
        d = json.load(f)
    print(str(d.get('integrations', {}).get('linear', {}).get('available', False)).lower())
except Exception:
    print('false')
" 2>/dev/null || echo "false"
}

# ── Emit ──────────────────────────────────────────────────────────────────

do_emit() {
  local available
  available="$(_linear_available)"

  # Build log entry
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)

  local entry
  entry=$(python3 -c "
import json, sys

event_type = sys.argv[1]
event_json_str = sys.argv[2]
linear_available = sys.argv[3] == 'true'
timestamp = sys.argv[4]

# Try to parse event payload; fall back to string
try:
    payload = json.loads(event_json_str)
except (json.JSONDecodeError, ValueError):
    payload = event_json_str

entry = {
    'timestamp': timestamp,
    'event_type': event_type,
    'linear_available': linear_available,
    'payload': payload
}
print(json.dumps(entry, separators=(',', ':')))
" "$EVENT_TYPE" "$EVENT_JSON" "$available" "$ts" 2>/dev/null) || true

  # If python3 failed to build the entry, build a minimal one
  if [[ -z "$entry" ]]; then
    entry="{\"timestamp\":\"${ts}\",\"event_type\":\"${EVENT_TYPE}\",\"linear_available\":false,\"payload\":\"error\"}"
  fi

  # Ensure directory exists
  mkdir -p "$(dirname "$LOG_FILE")"

  # Append entry
  echo "$entry" >> "$LOG_FILE"

  # Truncate to LOG_MAX entries (keep last LOG_MAX lines)
  local line_count
  line_count=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
  if [[ "$line_count" -gt "$LOG_MAX" ]]; then
    local tail_count=$LOG_MAX
    tail -n "$tail_count" "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null || true
  fi
}

# ── Dispatch (always exit 0) ─────────────────────────────────────────────

case "$CMD" in
  emit) do_emit ;;
esac

exit 0
