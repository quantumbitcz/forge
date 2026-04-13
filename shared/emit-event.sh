#!/usr/bin/env bash
# emit-event.sh — Append a structured event to .forge/events.jsonl.
#
# Usage: emit-event.sh <type> <stage> <agent> '<json_data>' [parent_id] [run_id]
#
# Arguments:
#   type       — One of the 12 event types (PIPELINE_START, PIPELINE_END, etc.)
#   stage      — Current pipeline stage (PREFLIGHT, EXPLORING, etc.)
#   agent      — Agent emitting the event (e.g., fg-100-orchestrator)
#   json_data  — JSON object for the type-specific data payload
#   parent_id  — (optional) ID of the causally preceding event. Default: null
#   run_id     — (optional) Run identifier. Default: read from state.json
#
# Output: Prints the assigned event ID on stdout for parent_id chaining.
# Exit: 0 on success or if .forge/ does not exist (graceful no-op).
#
# Sprint mode: callers MUST set FORGE_DIR to the per-run directory
# (e.g., .forge/runs/{id}/) to ensure event file isolation between
# concurrent pipeline instances. Without this, concurrent writes
# may interleave despite locking.
#       1 on usage error.
#
# Thread safety: mkdir-based locking (macOS compatible, no flock dependency).

set -euo pipefail

# ── Source platform helpers ──────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=platform.sh
source "${SCRIPT_DIR}/platform.sh"

# ── Locate .forge directory ──────────────────────────────────────────────────

_find_forge_dir() {
  # Walk up from CWD to find .forge/
  local dir
  dir="$(pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "${dir}/.forge" ]]; then
      printf '%s/.forge' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

FORGE_DIR="${FORGE_DIR:-$(_find_forge_dir 2>/dev/null || true)}"

# Graceful exit if .forge/ does not exist
if [[ -z "$FORGE_DIR" || ! -d "$FORGE_DIR" ]]; then
  exit 0
fi

# ── Validate arguments ───────────────────────────────────────────────────────

if [[ $# -lt 4 ]]; then
  echo "Usage: emit-event.sh <type> <stage> <agent> '<json_data>' [parent_id] [run_id]" >&2
  exit 1
fi

EVENT_TYPE="$1"
EVENT_STAGE="$2"
EVENT_AGENT="$3"
EVENT_DATA="$4"
PARENT_ID="${5:-null}"
RUN_ID="${6:-}"

# ── Validate event type ──────────────────────────────────────────────────────

VALID_TYPES="PIPELINE_START PIPELINE_END STAGE_TRANSITION AGENT_DISPATCH AGENT_COMPLETE FINDING DECISION STATE_WRITE RECOVERY USER_INTERACTION CONVERGENCE CHECKPOINT"

_valid_type=false
for t in $VALID_TYPES; do
  if [[ "$EVENT_TYPE" == "$t" ]]; then
    _valid_type=true
    break
  fi
done

if [[ "$_valid_type" != "true" ]]; then
  echo "ERROR: Invalid event type '$EVENT_TYPE'. Valid types: $VALID_TYPES" >&2
  exit 1
fi

# ── Resolve run_id from state.json if not provided ───────────────────────────

if [[ -z "$RUN_ID" ]]; then
  if [[ -f "${FORGE_DIR}/state.json" ]] && command -v jq &>/dev/null; then
    RUN_ID="$(jq -r '.run_id // empty' "${FORGE_DIR}/state.json" 2>/dev/null || true)"
  fi
  # Fallback: generate from date
  if [[ -z "$RUN_ID" ]]; then
    RUN_ID="run-$(date -u +%Y-%m-%dT%H%M%S)"
  fi
fi

# ── Event file path ──────────────────────────────────────────────────────────

EVENTS_FILE="${FORGE_DIR}/events.jsonl"
LOCK_DIR="${EVENTS_FILE}.lock"

# ── Generate timestamp ───────────────────────────────────────────────────────

_timestamp() {
  # ISO 8601 with millisecond precision
  if date -u +"%Y-%m-%dT%H:%M:%S.000Z" &>/dev/null; then
    # Try GNU date with nanoseconds first, fall back to static .000
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
    # On macOS, %3N is not supported and may produce literal "%3N"
    if [[ "$ts" == *"%3N"* ]]; then
      ts="$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
    fi
    printf '%s' "$ts"
  else
    printf '%s' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  fi
}

# ── Next sequence ID ─────────────────────────────────────────────────────────

_next_seq() {
  if [[ ! -f "$EVENTS_FILE" ]] || [[ ! -s "$EVENTS_FILE" ]]; then
    printf '1'
    return
  fi
  # Read the last line and extract id
  local last_id
  if command -v jq &>/dev/null; then
    last_id="$(tail -1 "$EVENTS_FILE" 2>/dev/null | jq -r '.id // 0' 2>/dev/null || echo 0)"
  else
    # Regex fallback
    last_id="$(tail -1 "$EVENTS_FILE" 2>/dev/null | grep -oE '"id"\s*:\s*[0-9]+' | head -1 | grep -oE '[0-9]+' || echo 0)"
  fi
  # Guard against non-numeric
  [[ "$last_id" =~ ^[0-9]+$ ]] || last_id=0
  printf '%d' $((last_id + 1))
}

# ── Format parent_id ─────────────────────────────────────────────────────────

_format_parent_id() {
  local pid="$1"
  if [[ "$pid" == "null" || -z "$pid" ]]; then
    printf 'null'
  else
    printf '%s' "$pid"
  fi
}

# ── Acquire lock, emit event, release lock ───────────────────────────────────

if ! acquire_lock_with_retry "$LOCK_DIR" 5; then
  # Lock contention — emit without lock as fallback (best effort)
  echo "WARNING: Could not acquire event log lock, writing without lock" >&2
fi

# Ensure lock cleanup on exit
_cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap _cleanup EXIT

# Get next ID (inside lock to prevent race)
EVENT_ID="$(_next_seq)"
EVENT_TS="$(_timestamp)"
FORMATTED_PARENT="$(_format_parent_id "$PARENT_ID")"

# Construct and append event
if command -v jq &>/dev/null; then
  EVENT_JSON="$(jq -nc \
    --argjson id "$EVENT_ID" \
    --arg ts "$EVENT_TS" \
    --arg type "$EVENT_TYPE" \
    --arg run_id "$RUN_ID" \
    --arg stage "$EVENT_STAGE" \
    --arg agent "$EVENT_AGENT" \
    --argjson parent_id "$FORMATTED_PARENT" \
    --argjson data "$EVENT_DATA" \
    '{id: $id, ts: $ts, type: $type, run_id: $run_id, stage: $stage, agent: $agent, parent_id: $parent_id, data: $data}' 2>/dev/null)"

  if [[ -n "$EVENT_JSON" ]]; then
    echo "$EVENT_JSON" >> "$EVENTS_FILE" 2>/dev/null || true
  fi
else
  # Fallback: manual JSON construction (no jq)
  echo "{\"id\":${EVENT_ID},\"ts\":\"${EVENT_TS}\",\"type\":\"${EVENT_TYPE}\",\"run_id\":\"${RUN_ID}\",\"stage\":\"${EVENT_STAGE}\",\"agent\":\"${EVENT_AGENT}\",\"parent_id\":${FORMATTED_PARENT},\"data\":${EVENT_DATA}}" >> "$EVENTS_FILE" 2>/dev/null || true
fi

# Output the event ID for parent_id chaining
printf '%s' "$EVENT_ID"
