#!/usr/bin/env bash
# Atomic JSON state writer with WAL (write-ahead log) and _seq versioning.
# Usage:
#   forge-state-write.sh write <json> [--forge-dir <path>]
#   forge-state-write.sh read [--forge-dir <path>]
#   forge-state-write.sh recover [--forge-dir <path>]
set -uo pipefail

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
  if ! echo "$JSON_CONTENT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    echo "ERROR: invalid JSON input" >&2
    exit 2
  fi

  # Acquire exclusive lock for the entire read-modify-write cycle.
  # Uses flock when available (Linux), falls back to mkdir-based lock (macOS).
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

  # Read current _seq from existing state.json (0 if not present)
  local current_seq=0
  if [[ -f "$STATE_FILE" ]]; then
    current_seq=$(python3 -c "
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
      if [[ "$_lock_mode" == "flock" ]]; then exec 200>&-; else rmdir "$lock_dir" 2>/dev/null; fi
      exit 2
    fi
  fi

  # Read input _seq
  local input_seq
  input_seq=$(echo "$JSON_CONTENT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('_seq', 0))")

  # Reject stale writes
  if [[ -f "$STATE_FILE" ]] && [[ "$input_seq" -lt "$current_seq" ]]; then
    echo "ERROR: stale write rejected (_seq $input_seq < current $current_seq)" >&2
    if [[ "$_lock_mode" == "flock" ]]; then exec 200>&-; else rmdir "$lock_dir" 2>/dev/null; fi
    exit 1
  fi

  # Increment _seq
  local new_seq=$((current_seq + 1))
  local updated_json
  updated_json=$(echo "$JSON_CONTENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['_seq'] = $new_seq
json.dump(d, sys.stdout, indent=2)
")

  # Append to WAL
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)
  {
    echo "--- SEQ:${new_seq} TS:${ts} ---"
    echo "$updated_json"
  } >> "$WAL_FILE"

  # Truncate WAL if over limit
  local wal_count
  wal_count=$(grep -c "^--- SEQ:" "$WAL_FILE" 2>/dev/null || echo "0")
  if [[ "$wal_count" -gt "$WAL_MAX_ENTRIES" ]]; then
    python3 -c "
import re, sys, os
with open('$WAL_FILE') as f:
    content = f.read()
entries = re.split(r'(?=^--- SEQ:)', content, flags=re.MULTILINE)
entries = [e for e in entries if e.strip()]
keep = entries[-$WAL_MAX_ENTRIES:]
with open('$WAL_FILE.tmp', 'w') as f:
    f.write(''.join(keep))
os.replace('$WAL_FILE.tmp', '$WAL_FILE')
"
  fi

  # Atomic write: tmp + mv
  echo "$updated_json" > "$TMP_FILE"
  mv "$TMP_FILE" "$STATE_FILE"

  # Release exclusive lock
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
    do_recover
    return $?
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
  recovered=$(python3 -c "
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
