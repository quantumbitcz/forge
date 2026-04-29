#!/usr/bin/env bash
# orchestrator-injection-gate.sh — injection-hardening confirmation gate.
# Decides whether a Confirmed-tier (T-C) data ingress to a Bash-capable agent
# may proceed. In interactive runs the orchestrator itself calls
# AskUserQuestion; this script is the non-interactive fallback for
# background/CI runs (see shared/background-execution.md).
#
# Exit codes:
#   0  = allow dispatch (gate did not fire)
#   1  = blocked + alerts.json written (autonomous T-C+Bash combination)
#   2  = usage error
#   3  = internal error (interactive path reached without AskUserQuestion)
set -euo pipefail

TIER=""
HAS_BASH=""
AUTONOMOUS="false"
FORGE_DIR=".forge"
AGENT=""
SOURCE=""
RUN_ID="${FORGE_RUN_ID:-unknown}"

while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="$2"; shift 2 ;;
    --has-bash) HAS_BASH="$2"; shift 2 ;;
    --autonomous) AUTONOMOUS="$2"; shift 2 ;;
    --forge-dir) FORGE_DIR="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ "$TIER" != "confirmed" ] || [ "$HAS_BASH" != "true" ]; then
  # Gate only fires on T-C + Bash combination.
  exit 0
fi

# T-C + Bash — in autonomous mode, fall back to alerts.json and pause.
if [ "$AUTONOMOUS" = "true" ]; then
  mkdir -p "$FORGE_DIR"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  alerts_path="$FORGE_DIR/alerts.json" \
    ts="$ts" agent="$AGENT" source_field="$SOURCE" run_id="$RUN_ID" \
  python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ["alerts_path"])
rec = {
  "ts": os.environ["ts"],
  "severity": "high",
  "reason": "T-C + Bash dispatch blocked",
  "agent": os.environ["agent"],
  "source": os.environ["source_field"],
  "run_id": os.environ["run_id"],
  "resume_hint": "Run /forge-admin recover resume after reviewing the ingress.",
}
p.write_text(json.dumps(rec, sort_keys=True, indent=2))
PY
  echo "injection-gate: paused (T-C + Bash, autonomous); wrote $FORGE_DIR/alerts.json" >&2
  exit 1
fi

# Interactive mode: orchestrator must have called AskUserQuestion before
# invoking us. Reaching here with autonomous=false is a programming error.
echo "injection-gate: interactive path reached without AskUserQuestion — internal error" >&2
exit 3
