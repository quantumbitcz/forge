#!/usr/bin/env bash
# preflight-injection-check.sh — Phase 03 Task 20.
# Refuses to start the pipeline when injection hardening is disabled, and
# performs the one-time historical scan of pre-3.x wiki/explore-cache content.
#
# Exit codes:
#   0 = OK (config sane, scan completed or already done)
#   1 = SEC-INJECTION-DISABLED — pipeline must halt
set -euo pipefail

CONFIG="${1:-forge-config.md}"
FORGE_DIR="${2:-.forge}"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$CONFIG" ]; then
  echo "preflight-injection-check: config $CONFIG not found (ok if defaults apply)"
  exit 0
fi

# Detect disabled untrusted_envelope.
if awk '/^[[:space:]]+untrusted_envelope:[[:space:]]*$/,/^[a-zA-Z]/' "$CONFIG" \
  | grep -Eq '^[[:space:]]+enabled:[[:space:]]*false[[:space:]]*$'; then
  echo "SEC-INJECTION-DISABLED CRITICAL: untrusted_envelope.enabled is false in $CONFIG" >&2
  exit 1
fi

# Detect disabled injection_detection.
if awk '/^[[:space:]]+injection_detection:[[:space:]]*$/,/^[a-zA-Z]/' "$CONFIG" \
  | grep -Eq '^[[:space:]]+enabled:[[:space:]]*false[[:space:]]*$'; then
  echo "SEC-INJECTION-DISABLED CRITICAL: injection_detection.enabled is false in $CONFIG" >&2
  exit 1
fi

# Historical retro-scan — runs once per install.
sentinel="$FORGE_DIR/security/.historical-scan-done"
if [ ! -f "$sentinel" ]; then
  mkdir -p "$FORGE_DIR/security"
  if [ -d "$FORGE_DIR/wiki" ] || [ -f "$FORGE_DIR/explore-cache.json" ]; then
    PYTHONPATH="$PLUGIN_ROOT" FORGE_DIR_ENV="$FORGE_DIR" \
    python3 - <<'PY' || true
import os, pathlib
import sys
sys.path.insert(0, os.environ["PYTHONPATH"])
from hooks._py import mcp_response_filter as f

forge_dir = pathlib.Path(os.environ["FORGE_DIR_ENV"])
run_id = "historical-scan"
targets = []
wiki = forge_dir / "wiki"
if wiki.is_dir():
    targets.extend((p, "wiki", str(p)) for p in wiki.rglob("*.md"))
ec = forge_dir / "explore-cache.json"
if ec.is_file():
    targets.append((ec, "explore-cache", str(ec)))
for path, source, origin in targets:
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    r = f.filter_response(source=source, origin=origin, content=content,
                          run_id=run_id, agent="preflight")
    for fd in r["findings"]:
        if fd["severity"] != "BLOCK":
            print(f"SEC-INJECTION-HISTORICAL INFO: {fd['pattern_id']} in {origin}")
PY
  fi
  : > "$sentinel"
fi

echo "preflight-injection-check: OK"
