#!/usr/bin/env bash
# Check if pipeline has exceeded its time budget.
# Exit 0 = within budget, exit 1 = exceeded, exit 0 + WARNING at 80%.
set -uo pipefail

FORGE_DIR="${1:-.forge}"
MAX_SECONDS="${2:-7200}"

STATE_FILE="${FORGE_DIR}/state.json"
[[ -f "$STATE_FILE" ]] || exit 0

# Path passed via argv (not interpolated into source) so MSYS path
# auto-conversion produces a native form on Windows.
start_ts=$("${FORGE_PYTHON:-python3}" - "$STATE_FILE" <<'PY' 2>/dev/null
import json
import sys
from pathlib import Path

try:
    with Path(sys.argv[1]).open() as f:
        d = json.load(f)
    ts = d.get('stage_timestamps', {}).get('preflight', '')
    print(ts)
except Exception:
    print('')
PY
)

[[ -z "$start_ts" ]] && exit 0

elapsed=$("${FORGE_PYTHON:-python3}" - "$start_ts" <<'PY'
import sys
from datetime import datetime, timezone

try:
    start = datetime.fromisoformat(sys.argv[1].replace('Z', '+00:00'))
    now = datetime.now(timezone.utc)
    print(int((now - start).total_seconds()))
except Exception:
    print(0)
PY
)

if (( elapsed >= MAX_SECONDS )); then
  echo "TIMEOUT: Pipeline running for ${elapsed}s (limit: ${MAX_SECONDS}s)"
  exit 1
fi

warning_threshold=$(( MAX_SECONDS * 80 / 100 ))
if (( elapsed >= warning_threshold )); then
  echo "WARNING: Pipeline at ${elapsed}s of ${MAX_SECONDS}s ($(( elapsed * 100 / MAX_SECONDS ))%)"
fi

exit 0
