#!/usr/bin/env bash
# Executable state machine for the forge pipeline.
# Encodes the complete 57-row transition table from state-transitions.md.
# Uses forge-state-write.sh for all state reads/writes.
#
# Commands:
#   init <story-id> <requirement> [--mode MODE] [--dry-run] [--forge-dir PATH]
#   query [--forge-dir PATH]
#   transition <event> [--guard key=value ...] [--forge-dir PATH]
#   reset <counter-group> [--forge-dir PATH]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_WRITER="${SCRIPT_DIR}/forge-state-write.sh"

# Source platform.sh for FORGE_PYTHON if available; fallback to python3
if [[ -f "${SCRIPT_DIR}/platform.sh" ]]; then
  source "${SCRIPT_DIR}/platform.sh"
fi
PYTHON="${FORGE_PYTHON:-python3}"
if [[ -z "$PYTHON" ]] || ! command -v "$PYTHON" &>/dev/null; then
  echo "ERROR: Python 3 is required. Install python3 and ensure it is on PATH." >&2
  exit 2
fi

# ── Argument parsing ─────────────────────────────────────────────────────

CMD=""
FORGE_DIR=".forge"
STORY_ID=""
REQUIREMENT=""
MODE="standard"
DRY_RUN="false"
EVENT=""
GUARDS=()
RESET_GROUP=""

parse_args() {
  [[ $# -eq 0 ]] && { usage; exit 2; }
  CMD="$1"; shift

  case "$CMD" in
    init)
      [[ $# -lt 2 ]] && { echo "ERROR: init requires <story-id> <requirement>" >&2; exit 2; }
      STORY_ID="$1"; shift
      REQUIREMENT="$1"; shift
      ;;
    query) ;;
    transition)
      [[ $# -lt 1 ]] && { echo "ERROR: transition requires <event>" >&2; exit 2; }
      EVENT="$1"; shift
      ;;
    reset)
      [[ $# -lt 1 ]] && { echo "ERROR: reset requires <counter-group>" >&2; exit 2; }
      RESET_GROUP="$1"; shift
      ;;
    *) echo "ERROR: unknown command: $CMD" >&2; usage; exit 2 ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --forge-dir) shift; FORGE_DIR="${1:?--forge-dir requires a path}"; shift ;;
      --mode)      shift; MODE="${1:?--mode requires a value}"; shift ;;
      --dry-run)   DRY_RUN="true"; shift ;;
      --guard)     shift; GUARDS+=("${1:?--guard requires key=value}"); shift ;;
      *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
  done
}

usage() {
  echo "Usage:" >&2
  echo "  forge-state.sh init <story-id> <requirement> [--mode MODE] [--dry-run] [--forge-dir PATH]" >&2
  echo "  forge-state.sh query [--forge-dir PATH]" >&2
  echo "  forge-state.sh transition <event> [--guard key=value ...] [--forge-dir PATH]" >&2
  echo "  forge-state.sh reset <counter-group> [--forge-dir PATH]" >&2
}

# ── Init ─────────────────────────────────────────────────────────────────

do_init() {
  local dry_run_val="false"
  [[ "$DRY_RUN" == "true" ]] && dry_run_val="true"

  local init_json
  init_json=$("$PYTHON" "$SCRIPT_DIR/python/state_init.py" "$STORY_ID" "$REQUIREMENT" "$MODE" "$dry_run_val")

  if [[ $? -ne 0 ]]; then
    echo "ERROR: failed to generate initial state JSON" >&2
    exit 2
  fi

  bash "$STATE_WRITER" write "$init_json" --forge-dir "$FORGE_DIR"
}

# ── Query ────────────────────────────────────────────────────────────────

do_query() {
  bash "$STATE_WRITER" read --forge-dir "$FORGE_DIR"
}

# ── Transition ───────────────────────────────────────────────────────────

do_transition() {
  # Acquire transition lock BEFORE reading state to prevent concurrent transitions
  local _transition_lock="${FORGE_DIR}/.transition.lock"

  if command -v flock &>/dev/null; then
    exec 201>"$_transition_lock"
    if ! flock -w 10 201; then
      echo "ERROR: transition lock timeout (another transition in progress)" >&2
      exec 201>&- 2>/dev/null
      return 2
    fi
    trap 'exec 201>&- 2>/dev/null; ' RETURN
  else
    local _retries=0
    while ! mkdir "${_transition_lock}.d" 2>/dev/null; do
      _retries=$((_retries + 1))
      if [ "$_retries" -ge 100 ]; then
        echo "ERROR: transition lock timeout (another transition in progress)" >&2
        return 2
      fi
      sleep 0.1
    done
    trap 'rmdir "${_transition_lock}.d" 2>/dev/null; ' RETURN
  fi

  local current_state_json
  current_state_json=$(bash "$STATE_WRITER" read --forge-dir "$FORGE_DIR")
  if [[ $? -ne 0 ]]; then
    echo "ERROR: failed to read current state" >&2
    return 2
  fi

  # Migrate state schema if needed
  local _version
  _version=$(printf '%s' "$current_state_json" | "$PYTHON" -c "import json,sys; print(json.load(sys.stdin).get('version','1.5.0'))")
  if [[ "$_version" != "1.6.0" ]]; then
    current_state_json=$(printf '%s' "$current_state_json" | "$PYTHON" "$SCRIPT_DIR/python/state_migrate.py")
    if [[ $? -eq 0 ]]; then
      bash "$STATE_WRITER" write "$current_state_json" --forge-dir "$FORGE_DIR"
    fi
  fi

  # Build guards JSON from --guard args
  local guards_json="{}"
  if [[ ${#GUARDS[@]} -gt 0 ]]; then
    guards_json=$("$PYTHON" "$SCRIPT_DIR/python/guard_parser.py" "${GUARDS[@]}")
  fi

  # Execute the transition via external Python module
  local result
  result=$(printf '%s' "$current_state_json" | "$PYTHON" "$SCRIPT_DIR/python/state_transitions.py" "$EVENT" "$guards_json" "$FORGE_DIR")

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$result"
    return 1
  fi

  # Extract updated state from the result JSON (state_transitions.py outputs everything to stdout)
  local state_json
  state_json=$(printf '%s' "$result" | "$PYTHON" -c "import json,sys; print(json.dumps(json.load(sys.stdin)['updated_state']))")
  if [[ $? -ne 0 || -z "$state_json" ]]; then
    echo "ERROR: failed to extract updated_state from transition result" >&2
    return 2
  fi

  # Write updated state via forge-state-write.sh
  bash "$STATE_WRITER" write "$state_json" --forge-dir "$FORGE_DIR" > /dev/null
  if [[ $? -ne 0 ]]; then
    echo "ERROR: failed to write updated state" >&2
    return 2
  fi

  # Emit state_transition event (fire-and-forget)
  local event_script="${SCRIPT_DIR}/forge-event.sh"
  if [[ -x "$event_script" ]]; then
    local _from _to _row
    _from=$("$PYTHON" -c "import json,sys;print(json.loads(sys.argv[1]).get('previous_state',''))" "$result" 2>/dev/null || true)
    _to=$("$PYTHON" -c "import json,sys;print(json.loads(sys.argv[1]).get('new_state',''))" "$result" 2>/dev/null || true)
    _row=$("$PYTHON" -c "import json,sys;print(json.loads(sys.argv[1]).get('row_id',json.loads(sys.argv[1]).get('row','')))" "$result" 2>/dev/null || true)
    bash "$event_script" state_transition \
      --field "from=${_from}" \
      --field "to=${_to}" \
      --field "trigger=${EVENT}" \
      --field "row=${_row}" \
      --forge-dir "$FORGE_DIR" 2>/dev/null || true
  fi

  # Output the result JSON
  echo "$result"
}

# ── Reset ────────────────────────────────────────────────────────────────

do_reset() {
  local current_state_json
  current_state_json=$(bash "$STATE_WRITER" read --forge-dir "$FORGE_DIR")
  if [[ $? -ne 0 ]]; then
    echo "ERROR: failed to read current state" >&2
    exit 2
  fi

  local updated_json
  updated_json=$("$PYTHON" -c "
import json, sys

state = json.loads(sys.argv[1])
group = sys.argv[2]

if group == 'implementation':
    state['quality_cycles'] = 0
    state['test_cycles'] = 0
elif group == 'design':
    state['quality_cycles'] = 0
    state['test_cycles'] = 0
    state['verify_fix_count'] = 0
    state['validation_retries'] = 0
else:
    print(json.dumps({'error': f'Unknown counter group: {group}'}))
    sys.exit(1)

print(json.dumps(state, indent=2))
" "$current_state_json" "$RESET_GROUP")

  if [[ $? -ne 0 ]]; then
    echo "$updated_json"
    return 1
  fi

  bash "$STATE_WRITER" write "$updated_json" --forge-dir "$FORGE_DIR" > /dev/null
  echo '{"reset": "'"$RESET_GROUP"'", "success": true}'
}

# ── Main ─────────────────────────────────────────────────────────────────

parse_args "$@"

case "$CMD" in
  init)       do_init ;;
  query)      do_query ;;
  transition) do_transition ;;
  reset)      do_reset ;;
esac
