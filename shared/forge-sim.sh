#!/usr/bin/env bash
# Pipeline simulation harness for forge.
# Feeds mock events through forge-state.sh and validates execution traces.
#
# Commands:
#   run <scenario.yaml> [--forge-dir <temp-dir>]
#   validate <trace-file>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_SCRIPT="${SCRIPT_DIR}/forge-state.sh"

# ── Usage ─────────────────────────────────────────────────────────────────

usage() {
  echo "Usage:" >&2
  echo "  forge-sim.sh run <scenario.yaml> [--forge-dir <temp-dir>]" >&2
  echo "  forge-sim.sh validate <trace-file>" >&2
  exit 2
}

# ── Run command ───────────────────────────────────────────────────────────

do_run() {
  local scenario_file="$1"
  local forge_dir="${2:-}"

  if [[ ! -f "$scenario_file" ]]; then
    echo "ERROR: scenario file not found: $scenario_file" >&2
    exit 2
  fi

  # Parse scenario YAML and run simulation via Python
  python3 "${SCRIPT_DIR}/forge-sim-runner.py" \
    "$scenario_file" \
    "$STATE_SCRIPT" \
    "$forge_dir"
}

# ── Validate command ──────────────────────────────────────────────────────

do_validate() {
  local trace_file="$1"
  if [[ ! -f "$trace_file" ]]; then
    echo "ERROR: trace file not found: $trace_file" >&2
    exit 2
  fi
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
if not isinstance(data, list):
    print('ERROR: trace must be a JSON array', file=sys.stderr)
    sys.exit(1)
for i, entry in enumerate(data):
    if not isinstance(entry, str) or ' -> ' not in entry:
        print(f'ERROR: trace entry {i} is not a valid transition: {entry}', file=sys.stderr)
        sys.exit(1)
print('PASS: trace format valid')
" "$trace_file"
}

# ── Main ──────────────────────────────────────────────────────────────────

[[ $# -eq 0 ]] && usage

CMD="$1"; shift

case "$CMD" in
  run)
    [[ $# -lt 1 ]] && { echo "ERROR: run requires <scenario.yaml>" >&2; usage; }
    SCENARIO="$1"; shift
    FORGE_DIR=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --forge-dir) shift; FORGE_DIR="${1:?--forge-dir requires a path}"; shift ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage ;;
      esac
    done
    do_run "$SCENARIO" "$FORGE_DIR"
    ;;
  validate)
    [[ $# -lt 1 ]] && { echo "ERROR: validate requires <trace-file>" >&2; usage; }
    do_validate "$1"
    ;;
  *)
    echo "ERROR: unknown command: $CMD" >&2
    usage
    ;;
esac
