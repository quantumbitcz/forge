#!/usr/bin/env bash
# Token budget tracker for the forge pipeline.
# Estimates token counts, records usage per stage/agent, and checks budget ceiling.
#
# Commands:
#   estimate <file-path>                                                    — rough token count (chars / 4)
#   record <stage> <agent> <input> <output> [model] [--forge-dir PATH]     — accumulate usage in state.json
#   check [--forge-dir PATH]                                                — exit 0=OK, 1=warning (>=80%), 2=exceeded
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
MODEL=""

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
      # Optional 5th positional: model (skip if looks like a flag)
      if [[ $# -gt 0 && "${1:0:2}" != "--" ]]; then
        MODEL="$1"; shift
      fi
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

# Shared Python script for token accumulation, model distribution, and cost estimation.
# Used by both the primary record path and the stale-_seq retry path.
# shellcheck disable=SC2016
_TOKEN_UPDATE_PY='
import json, sys

state = json.load(sys.stdin)
stage = sys.argv[1]
agent = sys.argv[2]
input_t = int(sys.argv[3])
output_t = int(sys.argv[4])
model = sys.argv[5] if len(sys.argv) > 5 else ""

# Ensure tokens section exists
if "tokens" not in state:
    state["tokens"] = {
        "estimated_total": 0,
        "budget_ceiling": 0,
        "by_stage": {},
        "by_agent": {},
        "model_distribution": {},
        "budget_warning_issued": False,
    }

tokens = state["tokens"]

# Ensure model_distribution exists
if "model_distribution" not in tokens:
    tokens["model_distribution"] = {}

# Accumulate by_stage (with agents tracking)
if stage not in tokens["by_stage"]:
    tokens["by_stage"][stage] = {"input": 0, "output": 0, "agents": []}
bs = tokens["by_stage"][stage]
bs["input"] = bs.get("input", 0) + input_t
bs["output"] = bs.get("output", 0) + output_t
if "agents" not in bs:
    bs["agents"] = []
if agent not in bs["agents"]:
    bs["agents"].append(agent)

# Accumulate by_agent (with model tracking)
if agent not in tokens["by_agent"]:
    tokens["by_agent"][agent] = {"input": 0, "output": 0, "model": ""}
ba = tokens["by_agent"][agent]
ba["input"] = ba.get("input", 0) + input_t
ba["output"] = ba.get("output", 0) + output_t
if model:
    ba["model"] = model

# Update estimated_total
tokens["estimated_total"] += input_t + output_t

# Recompute model_distribution from by_agent data
model_totals = {}
grand_total = 0
for a_name, a_data in tokens["by_agent"].items():
    a_total = a_data.get("input", 0) + a_data.get("output", 0)
    m = a_data.get("model", "") or ""
    if not m:
        m = "unknown"
    model_totals[m] = model_totals.get(m, 0) + a_total
    grand_total += a_total
if grand_total > 0:
    tokens["model_distribution"] = {m: round(t / grand_total, 4) for m, t in model_totals.items()}
else:
    tokens["model_distribution"] = {}

# Compute estimated_cost_usd using approximate pricing (per million tokens)
# Pricing per MTok as of April 2026 — update when Anthropic adjusts pricing
# See: https://docs.anthropic.com/en/docs/about-claude/models for current rates
PRICING = {
    "haiku":   {"input": 0.25,  "output": 1.25},
    "sonnet":  {"input": 3.0,   "output": 15.0},
    "opus":    {"input": 15.0,  "output": 75.0},
}
DEFAULT_PRICING = PRICING["sonnet"]

total_cost = 0.0
for a_name, a_data in tokens["by_agent"].items():
    m = a_data.get("model", "") or ""
    pricing = DEFAULT_PRICING
    for key in PRICING:
        if key in m.lower():
            pricing = PRICING[key]
            break
    total_cost += a_data.get("input", 0) * pricing["input"] / 1_000_000
    total_cost += a_data.get("output", 0) * pricing["output"] / 1_000_000

# Update cost section
if "cost" not in state:
    state["cost"] = {"wall_time_seconds": 0, "stages_completed": 0, "estimated_cost_usd": 0.0}
state["cost"]["estimated_cost_usd"] = round(total_cost, 6)

json.dump(state, sys.stdout, indent=2)
'

# Run the shared Python token-update script against the current state JSON.
# Arguments are forwarded as: stage agent input_tokens output_tokens [model]
_compute_token_update() {
  echo "$1" | python3 -c "$_TOKEN_UPDATE_PY" "$STAGE" "$AGENT" "$INPUT_TOKENS" "$OUTPUT_TOKENS" "$MODEL"
}

do_record() {
  local state_file="${FORGE_DIR}/state.json"
  [[ ! -f "$state_file" ]] && { echo "ERROR: state.json not found in $FORGE_DIR" >&2; exit 2; }

  # Read current state
  local current_state
  current_state=$(bash "$STATE_WRITER" read --forge-dir "$FORGE_DIR")
  [[ $? -ne 0 ]] && { echo "ERROR: failed to read state.json" >&2; exit 2; }

  # Update tokens section via python3
  local updated_state
  updated_state=$(_compute_token_update "$current_state")
  [[ $? -ne 0 ]] && { echo "ERROR: failed to compute token update" >&2; exit 2; }

  # Write back via state writer (with retry on stale _seq)
  local _max_retries=3 _attempt=0
  while true; do
    bash "$STATE_WRITER" write "$updated_state" --forge-dir "$FORGE_DIR" > /dev/null
    local _rc=$?
    if [[ $_rc -eq 0 ]]; then
      break
    elif [[ $_rc -eq 3 && $_attempt -lt $_max_retries ]]; then
      # Stale _seq: re-read, recompute, retry
      _attempt=$((_attempt + 1))
      current_state=$(bash "$STATE_WRITER" read --forge-dir "$FORGE_DIR")
      [[ $? -ne 0 ]] && { echo "ERROR: re-read failed on retry $_attempt" >&2; exit 2; }
      updated_state=$(_compute_token_update "$current_state")
      [[ $? -ne 0 ]] && { echo "ERROR: recompute failed on retry $_attempt" >&2; exit 2; }
    else
      echo "ERROR: token update write failed (rc=$_rc, attempt=$_attempt)" >&2
      exit 2
    fi
  done
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
