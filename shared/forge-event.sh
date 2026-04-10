#!/usr/bin/env bash
# Emits a structured pipeline event to .forge/events.jsonl.
#
# Usage: forge-event.sh <event_type> [--field key=value]... [--forge-dir PATH]
#
# Example:
#   forge-event.sh state_transition --field from=IMPLEMENTING --field to=VERIFYING
#
# Event schema (JSONL, one object per line):
#   {"ts":"2026-04-09T10:30:00Z","event":"state_transition","run_id":"feat-x","seq":42,"fields":{"from":"IMPLEMENTING","to":"VERIFYING"}}
#
# Fire-and-forget: never returns non-zero for write failures.
# Missing .forge/ directory: creates events.jsonl in the specified --forge-dir.
set -uo pipefail

FORGE_DIR=".forge"
EVENT_TYPE=""
FIELDS=()

# ── Argument parsing ─────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  echo "Usage: forge-event.sh <event_type> [--field key=value]... [--forge-dir PATH]" >&2
  exit 2
fi

# First positional arg that doesn't start with -- is the event type
while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir)
      shift
      FORGE_DIR="${1:?--forge-dir requires a path}"
      shift
      ;;
    --field)
      shift
      FIELDS+=("${1:?--field requires key=value}")
      shift
      ;;
    --*)
      echo "ERROR: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$EVENT_TYPE" ]]; then
        EVENT_TYPE="$1"
      else
        echo "ERROR: unexpected argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$EVENT_TYPE" ]]; then
  echo "ERROR: event type is required" >&2
  exit 2
fi

# ── Emit event ───────────────────────────────────────────────────────────

EVENTS_FILE="${FORGE_DIR}/events.jsonl"

# Determine seq by counting existing lines
SEQ=1
if [[ -f "$EVENTS_FILE" ]]; then
  SEQ=$(( $(wc -l < "$EVENTS_FILE" | tr -d ' ') + 1 ))
fi

# Read run_id from state.json if available
RUN_ID=""
STATE_FILE="${FORGE_DIR}/state.json"
if [[ -f "$STATE_FILE" ]]; then
  RUN_ID=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    print(data.get('run_id', ''))
except Exception:
    print('')
" "$STATE_FILE" 2>/dev/null || true)
fi

# Build and append the event JSON
python3 -c "
import json, sys, datetime

event_type = sys.argv[1]
seq = int(sys.argv[2])
run_id = sys.argv[3]
events_file = sys.argv[4]
field_args = sys.argv[5:]

fields = {}
for arg in field_args:
    if '=' in arg:
        k, v = arg.split('=', 1)
        fields[k] = v

event = {
    'ts': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'event': event_type,
    'run_id': run_id,
    'seq': seq,
    'fields': fields
}

with open(events_file, 'a') as f:
    f.write(json.dumps(event, separators=(',', ':')) + '\n')
" "$EVENT_TYPE" "$SEQ" "$RUN_ID" "$EVENTS_FILE" "${FIELDS[@]+"${FIELDS[@]}"}" 2>/dev/null

# Fire-and-forget: always exit 0 even if the write above failed
exit 0
