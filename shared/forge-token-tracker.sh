#!/usr/bin/env bash
# Token budget tracker for the forge pipeline.
# Estimates token counts, records usage per stage/agent, and checks budget ceiling.
#
# Commands:
#   estimate <file-path>                                        — rough token count (chars / 4)
#   record <stage> <agent> <input> <output> [--forge-dir PATH]  — accumulate usage in state.json
#   check [--forge-dir PATH]                                    — exit 0=OK, 1=warning (>=80%), 2=exceeded
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_WRITER="${SCRIPT_DIR}/forge-state-write.sh"

FORGE_DIR=".forge"
CMD=""
FILE_PATH=""
STAGE=""
AGENT=""
INPUT_TOKENS=""
OUTPUT_TOKENS=""

# ── Argument parsing ──────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    estimate)
      CMD="estimate"
      shift
      FILE_PATH="${1:?estimate requires a file path}"
      shift
      ;;
    record)
      CMD="record"
      shift
      STAGE="${1:?record requires <stage>}"; shift
      AGENT="${1:?record requires <agent-name>}"; shift
      INPUT_TOKENS="${1:?record requires <input-tokens>}"; shift
      OUTPUT_TOKENS="${1:?record requires <output-tokens>}"; shift
      ;;
    check)
      CMD="check"
      shift
      ;;
    --forge-dir)
      shift
      FORGE_DIR="${1:?--forge-dir requires a path}"
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

[[ -z "$CMD" ]] && { echo "Usage: forge-token-tracker.sh {estimate|record|check} ..." >&2; exit 2; }

# ── Estimate ──────────────────────────────────────────────────────────────

do_estimate() {
  [[ ! -f "$FILE_PATH" ]] && { echo "ERROR: file not found: $FILE_PATH" >&2; exit 2; }
  python3 -c "
import os, sys
size = os.path.getsize(sys.argv[1])
print(size // 4)
" "$FILE_PATH"
}

# ── Record ────────────────────────────────────────────────────────────────

do_record() {
  local state_file="${FORGE_DIR}/state.json"
  [[ ! -f "$state_file" ]] && { echo "ERROR: state.json not found in $FORGE_DIR" >&2; exit 2; }

  # Read current state
  local current_state
  current_state=$(bash "$STATE_WRITER" read --forge-dir "$FORGE_DIR")
  [[ $? -ne 0 ]] && { echo "ERROR: failed to read state.json" >&2; exit 2; }

  # Update tokens section via python3
  local updated_state
  updated_state=$(echo "$current_state" | python3 -c "
import json, sys

state = json.load(sys.stdin)
stage = '$STAGE'
agent = '$AGENT'
input_t = int('$INPUT_TOKENS')
output_t = int('$OUTPUT_TOKENS')

# Ensure tokens section exists
if 'tokens' not in state:
    state['tokens'] = {
        'estimated_total': 0,
        'budget_ceiling': 0,
        'by_stage': {},
        'by_agent': {},
        'budget_warning_issued': False
    }

tokens = state['tokens']

# Accumulate by_stage
if stage not in tokens['by_stage']:
    tokens['by_stage'][stage] = {'input': 0, 'output': 0}
tokens['by_stage'][stage]['input'] += input_t
tokens['by_stage'][stage]['output'] += output_t

# Accumulate by_agent
if agent not in tokens['by_agent']:
    tokens['by_agent'][agent] = {'input': 0, 'output': 0}
tokens['by_agent'][agent]['input'] += input_t
tokens['by_agent'][agent]['output'] += output_t

# Update estimated_total
tokens['estimated_total'] += input_t + output_t

json.dump(state, sys.stdout, indent=2)
")

  [[ $? -ne 0 ]] && { echo "ERROR: failed to compute token update" >&2; exit 2; }

  # Write back via state writer
  bash "$STATE_WRITER" write "$updated_state" --forge-dir "$FORGE_DIR" > /dev/null
}

# ── Check ─────────────────────────────────────────────────────────────────

do_check() {
  local state_file="${FORGE_DIR}/state.json"
  [[ ! -f "$state_file" ]] && { echo "OK: no state.json, nothing to check"; exit 0; }

  local current_state
  current_state=$(bash "$STATE_WRITER" read --forge-dir "$FORGE_DIR")
  [[ $? -ne 0 ]] && { echo "OK: could not read state.json"; exit 0; }

  python3 -c "
import json, sys

state = json.loads(sys.argv[1])
tokens = state.get('tokens', {})
total = tokens.get('estimated_total', 0)
ceiling = tokens.get('budget_ceiling', 0)

if ceiling <= 0:
    print('OK: no budget ceiling set')
    sys.exit(0)

ratio = total / ceiling

if ratio >= 1.0:
    print(f'EXCEEDED: {total:,} tokens used, budget is {ceiling:,}')
    sys.exit(2)
elif ratio >= 0.8:
    pct = int(ratio * 100)
    print(f'WARNING: {pct}% of token budget used ({total:,} / {ceiling:,})')
    sys.exit(1)
else:
    pct = int(ratio * 100)
    print(f'OK: {pct}% of token budget used ({total:,} / {ceiling:,})')
    sys.exit(0)
" "$current_state"
}

# ── Dispatch ──────────────────────────────────────────────────────────────

case "$CMD" in
  estimate) do_estimate ;;
  record)   do_record ;;
  check)    do_check ;;
esac
