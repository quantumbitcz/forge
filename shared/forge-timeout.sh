#!/usr/bin/env bash
# Check if pipeline has exceeded its time budget.
# Exit 0 = within budget, exit 1 = exceeded, exit 0 + WARNING at 80%.
set -uo pipefail

FORGE_DIR="${1:-.forge}"
MAX_SECONDS="${2:-7200}"

STATE_FILE="${FORGE_DIR}/state.json"
[[ -f "$STATE_FILE" ]] || exit 0

start_ts=$(python3 -c "
import json, sys
try:
    with open('$STATE_FILE') as f:
        d = json.load(f)
    ts = d.get('stage_timestamps', {}).get('preflight', '')
    print(ts)
except:
    print('')
" 2>/dev/null)

[[ -z "$start_ts" ]] && exit 0

elapsed=$(python3 -c "
from datetime import datetime, timezone
import sys
try:
    start = datetime.fromisoformat('$start_ts'.replace('Z','+00:00'))
    now = datetime.now(timezone.utc)
    print(int((now - start).total_seconds()))
except:
    print(0)
")

if (( elapsed >= MAX_SECONDS )); then
  echo "TIMEOUT: Pipeline running for ${elapsed}s (limit: ${MAX_SECONDS}s)"
  exit 1
fi

warning_threshold=$(( MAX_SECONDS * 80 / 100 ))
if (( elapsed >= warning_threshold )); then
  echo "WARNING: Pipeline at ${elapsed}s of ${MAX_SECONDS}s ($(( elapsed * 100 / MAX_SECONDS ))%)"
fi

exit 0
