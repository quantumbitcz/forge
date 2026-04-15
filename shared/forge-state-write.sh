#!/usr/bin/env bash
# Atomic JSON state writer with WAL (write-ahead log) and _seq versioning.
# Usage:
#   forge-state-write.sh write <json> [--forge-dir <path>]   # exit 0=OK, 2=usage/validation, 3=stale write
#   forge-state-write.sh read [--forge-dir <path>]
#   forge-state-write.sh recover [--forge-dir <path>]
set -uo pipefail

PYTHON="${FORGE_PYTHON:-python3}"

# Rotate log files when they exceed max size
_rotate_log_if_needed() {
  local log_file="$1"
  local max_size="${2:-102400}"  # Default 100KB
  if [[ -f "$log_file" ]]; then
    local size
    size=$(wc -c < "$log_file" 2>/dev/null || echo 0)
    if [[ "$size" -gt "$max_size" ]]; then
      tail -1000 "$log_file" > "${log_file}.tmp" 2>/dev/null && \
        mv "${log_file}.tmp" "$log_file" 2>/dev/null || \
        rm -f "${log_file}.tmp" 2>/dev/null
    fi
  fi
}

_log_warning() {
  local reason="$1"
  local log_dir="${FORGE_DIR:-.forge}"
  if [[ -d "$log_dir" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | WARNING | state-write | $reason" \
      >> "${log_dir}/forge.log" 2>/dev/null || true
    _rotate_log_if_needed "${log_dir}/forge.log"
  fi
}

FORGE_DIR=".forge"
CMD=""
JSON_CONTENT=""
WAL_MAX_ENTRIES=50

# ── Argument parsing ──────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    write)
      CMD="write"
      shift
      if [[ "${1:-}" == --* ]]; then
        echo "ERROR: write requires JSON content as first argument after 'write'" >&2
        exit 2
      fi
      JSON_CONTENT="${1:-}"
      shift
      ;;
    read)    CMD="read"; shift ;;
    recover) CMD="recover"; shift ;;
    --forge-dir) shift; FORGE_DIR="${1:?--forge-dir requires a path}"; shift ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$CMD" ]] && { echo "Usage: forge-state-write.sh {write|read|recover} [--forge-dir <path>]" >&2; exit 2; }

STATE_FILE="${FORGE_DIR}/state.json"
WAL_FILE="${FORGE_DIR}/state.wal"
TMP_FILE="${FORGE_DIR}/state.json.tmp"

# ── Write ─────────────────────────────────────────────────────────────────

do_write() {
  [[ -z "$JSON_CONTENT" ]] && { echo "ERROR: write requires JSON content" >&2; exit 2; }

  # Validate input is valid JSON
  if ! echo "$JSON_CONTENT" | "$PYTHON" -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    echo "ERROR: invalid JSON input" >&2
    exit 2
  fi

  # Acquire exclusive lock for the entire read-modify-write cycle.
  # Uses flock when available (Linux), falls back to mkdir-based lock (MacOS).
  local _lock_mode=""
  local lock_file="${FORGE_DIR}/.state-write.lock"
  local lock_dir="${FORGE_DIR}/.state-write.lockdir"
  if command -v flock &>/dev/null; then
    _lock_mode="flock"
    exec 200>"$lock_file"
    flock -x 200
  else
    _lock_mode="mkdir"
    local _lock_attempts=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
      _lock_attempts=$((_lock_attempts + 1))
      if [[ $_lock_attempts -ge 50 ]]; then
        echo "ERROR: failed to acquire write lock after 5s" >&2
        exit 2
      fi
      sleep 0.1
    done
  fi

  # Release lock on any exit path (error, signal, etc.)
  trap 'if [[ "${_lock_mode:-}" == "flock" ]]; then exec 200>&- 2>/dev/null; elif [[ -d "${lock_dir:-}" ]]; then rmdir "$lock_dir" 2>/dev/null; fi' EXIT

  # Read current _seq from existing state.json (0 if not present)
  local current_seq=0
  if [[ -f "$STATE_FILE" ]]; then
    current_seq=$("$PYTHON" -c "
import json, sys
try:
    with open('$STATE_FILE') as f:
        print(json.load(f).get('_seq', 0))
except json.JSONDecodeError:
    print(0)
except Exception as e:
    print('READ_ERROR: ' + str(e), file=sys.stderr)
    sys.exit(1)
")
    if [[ $? -ne 0 ]]; then
      echo "ERROR: failed to read current state.json" >&2
      exit 2
    fi
  fi

  # Read input _seq
  local input_seq
  input_seq=$(echo "$JSON_CONTENT" | "$PYTHON" -c "import json,sys; print(json.load(sys.stdin).get('_seq', 0))")

  # Reject stale writes
  if [[ -f "$STATE_FILE" ]] && [[ "$input_seq" -lt "$current_seq" ]]; then
    echo "ERROR: stale write rejected (_seq $input_seq < current $current_seq)" >&2
    exit 3
  fi

  # Increment _seq
  local new_seq=$((current_seq + 1))
  local updated_json
  updated_json=$(echo "$JSON_CONTENT" | "$PYTHON" -c "
import json, sys
d = json.load(sys.stdin)
d['_seq'] = $new_seq
json.dump(d, sys.stdout, indent=2)
")

  # Advisory schema validation (never blocks writes)
  if [[ "${VALIDATE:-true}" != "false" ]]; then
    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local validation_result
    validation_result=$("$PYTHON" -c "
import json, sys
try:
    from jsonschema import validate, ValidationError
    schema_path = sys.argv[2]
    with open(schema_path) as f:
        schema = json.load(f)
    state = json.loads(sys.argv[1])
    validate(instance=state, schema=schema)
    print('OK')
except ImportError:
    print('SKIP')
except ValidationError as e:
    print('FAIL: ' + e.message)
except Exception as e:
    print('SKIP')
" "$updated_json" "${SCRIPT_DIR}/state-schema.json" 2>/dev/null || echo "SKIP")

    if [[ "$validation_result" == FAIL:* ]]; then
      echo "WARNING: State validation failed: ${validation_result#FAIL: }" >&2
    fi
  else
    _log_warning "schema validation SKIPPED (VALIDATE=false)"
  fi

  # Append to WAL
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  {
    echo "--- SEQ:${new_seq} TS:${ts} ---"
    echo "$updated_json"
  } >> "$WAL_FILE"

  # Truncate WAL if over limit (inside write lock scope)
  local wal_count
  wal_count=$(grep -c "^--- SEQ:" "$WAL_FILE" 2>/dev/null || echo "0")
  if [[ "$wal_count" -gt "$WAL_MAX_ENTRIES" ]]; then
    "$PYTHON" -c "
import re, sys, os
try:
    with open('$WAL_FILE') as f:
        content = f.read()
    entries = re.split(r'(?=^--- SEQ:)', content, flags=re.MULTILINE)
    entries = [e for e in entries if e.strip()]
    keep = entries[-$WAL_MAX_ENTRIES:]
    tmp_path = '$WAL_FILE.tmp'
    with open(tmp_path, 'w') as f:
        f.write(''.join(keep))
    os.replace(tmp_path, '$WAL_FILE')
except Exception as e:
    try:
        os.remove('$WAL_FILE.tmp')
    except OSError:
        pass
    print(f'WARNING: WAL truncation failed: {e}', file=sys.stderr)
" 2>/dev/null || {
      rm -f "${WAL_FILE}.tmp" 2>/dev/null
      _log_warning "WAL truncation failed, wal_count=${wal_count}"
    }
  fi

  # Atomic write: tmp + mv
  echo "$updated_json" > "$TMP_FILE"
  mv "$TMP_FILE" "$STATE_FILE"

  # Clear the EXIT trap (lock released by trap on error paths)
  trap - EXIT
  # Release exclusive lock on success
  if [[ "$_lock_mode" == "flock" ]]; then
    exec 200>&-
  else
    rmdir "$lock_dir" 2>/dev/null
  fi

  echo "$updated_json"
}

# ── Read ──────────────────────────────────────────────────────────────────

do_read() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
    return 0
  fi

  if [[ -f "$WAL_FILE" ]]; then
    echo "WARNING: state.json missing, recovering from WAL" >&2
    (
      if command -v flock &>/dev/null; then
        flock -w 5 200 || { echo '{}'; return; }
      else
        local lock_dir="${FORGE_DIR}/.state-write.lockdir.read"
        local attempts=0
        while ! mkdir "$lock_dir" 2>/dev/null; do
          attempts=$((attempts + 1))
          [[ $attempts -ge 50 ]] && { echo '{}'; return; }
          sleep 0.1
        done
        trap "rmdir '$lock_dir' 2>/dev/null" RETURN
      fi
      # Re-check under lock (another process may have recovered)
      if [[ ! -f "$STATE_FILE" ]] && [[ -f "$WAL_FILE" ]]; then
        do_recover
      fi
    ) 200>"${FORGE_DIR}/.state-read.lock"
    if [[ -f "$STATE_FILE" ]]; then
      cat "$STATE_FILE"
      return 0
    fi
    return 1
  fi

  echo "ERROR: no state.json or WAL found in $FORGE_DIR" >&2
  return 1
}

# ── Recover ───────────────────────────────────────────────────────────────

do_recover() {
  if [[ ! -f "$WAL_FILE" ]]; then
    echo "ERROR: no WAL file found at $WAL_FILE" >&2
    return 1
  fi

  # Split declaration from assignment to preserve $? from python3 subshell
  local recovered
  recovered=$("$PYTHON" -c "
import re, json, sys
with open('$WAL_FILE') as f:
    content = f.read()
entries = re.split(r'^--- SEQ:\d+ TS:\S+ ---$', content, flags=re.MULTILINE)
entries = [e.strip() for e in entries if e.strip()]
if not entries:
    sys.exit(1)
for entry in reversed(entries):
    try:
        d = json.loads(entry)
        json.dump(d, sys.stdout, indent=2)
        sys.exit(0)
    except json.JSONDecodeError:
        continue
sys.exit(1)
")

  if [[ $? -ne 0 ]] || [[ -z "$recovered" ]]; then
    echo "ERROR: no valid JSON found in WAL" >&2
    return 1
  fi

  echo "$recovered" > "$TMP_FILE"
  mv "$TMP_FILE" "$STATE_FILE"
  cat "$STATE_FILE"
}

# ── Dispatch ──────────────────────────────────────────────────────────────

case "$CMD" in
  write)   do_write ;;
  read)    do_read ;;
  recover) do_recover ;;
esac
