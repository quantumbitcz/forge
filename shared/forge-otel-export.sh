#!/usr/bin/env bash
# Export pipeline telemetry from state.json to an OTel collector.
#
# Usage:
#   forge-otel-export.sh export --endpoint <url> [--forge-dir <path>]
#   forge-otel-export.sh check  --endpoint <url>
#
# Export reads state.json.telemetry, converts spans to OTLP HTTP/JSON,
# and POSTs to {endpoint}/v1/traces. Failures are non-fatal (exit 0 + WARNING).
# Updates telemetry.export_status to "exported" or "failed".
set -euo pipefail

FORGE_DIR=".forge"
ENDPOINT=""
CMD=""

# ── Argument parsing ─────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    export)   CMD="export"; shift ;;
    check)    CMD="check"; shift ;;
    --forge-dir)
      shift
      FORGE_DIR="${1:?--forge-dir requires a path}"
      shift
      ;;
    --endpoint)
      shift
      ENDPOINT="${1:?--endpoint requires a URL}"
      shift
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$CMD" ]]; then
  echo "Usage: forge-otel-export.sh {export|check} --endpoint <url> [--forge-dir <path>]" >&2
  exit 2
fi

if [[ -z "$ENDPOINT" ]]; then
  echo "ERROR: --endpoint is required" >&2
  exit 2
fi

# Strip trailing slash
ENDPOINT="${ENDPOINT%/}"

STATE_FILE="${FORGE_DIR}/state.json"

# ── Check ────────────────────────────────────────────────────────────────

do_check() {
  if curl -sf --head --max-time 5 "${ENDPOINT}/v1/traces" >/dev/null 2>&1; then
    echo "OK: OTel endpoint reachable at ${ENDPOINT}"
    exit 0
  else
    echo "WARNING: OTel endpoint unreachable at ${ENDPOINT}"
    exit 1
  fi
}

# ── Export ───────────────────────────────────────────────────────────────

do_export() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "WARNING: No state.json found at ${STATE_FILE} — skipping export"
    exit 0
  fi

  # Extract telemetry and convert to OTLP JSON, then POST
  local otlp_json
  otlp_json=$(python3 -c "
import json, sys, hashlib, time

state_file = sys.argv[1]

with open(state_file) as f:
    state = json.load(f)

telemetry = state.get('telemetry')
if not telemetry:
    print('NO_TELEMETRY', file=sys.stderr)
    sys.exit(0)

spans = telemetry.get('spans', [])
if not spans:
    print('NO_SPANS', file=sys.stderr)
    sys.exit(0)

# Derive a trace ID from story_id for consistency
story_id = state.get('story_id', 'unknown')
trace_id = hashlib.md5(story_id.encode()).hexdigest()

def iso_to_nanos(iso_str):
    \"\"\"Convert ISO 8601 timestamp to nanoseconds since epoch.\"\"\"
    from datetime import datetime, timezone
    try:
        dt = datetime.fromisoformat(iso_str.replace('Z', '+00:00'))
        return int(dt.timestamp() * 1_000_000_000)
    except Exception:
        return int(time.time() * 1_000_000_000)

def make_span_id(name, start):
    \"\"\"Deterministic 16-hex-char span ID from name + start.\"\"\"
    return hashlib.md5(f'{name}:{start}'.encode()).hexdigest()[:16]

otlp_spans = []
for s in spans:
    span_name = s.get('name', '')
    start_ns = iso_to_nanos(s.get('start', ''))
    end_ns = iso_to_nanos(s.get('end', s.get('start', '')))
    span_id = make_span_id(span_name, s.get('start', ''))

    attrs = []
    for key in ('type', 'agent', 'model'):
        if s.get(key):
            attrs.append({'key': key, 'value': {'stringValue': str(s[key])}})
    for key in ('tokens_in', 'tokens_out', 'findings_count'):
        if s.get(key) is not None:
            attrs.append({'key': key, 'value': {'intValue': str(s[key])}})

    otlp_spans.append({
        'traceId': trace_id,
        'spanId': span_id,
        'name': span_name,
        'startTimeUnixNano': str(start_ns),
        'endTimeUnixNano': str(end_ns),
        'attributes': attrs,
    })

payload = {
    'resourceSpans': [{
        'resource': {
            'attributes': [
                {'key': 'service.name', 'value': {'stringValue': 'forge-pipeline'}},
                {'key': 'forge.story_id', 'value': {'stringValue': story_id}},
            ]
        },
        'scopeSpans': [{
            'scope': {'name': 'forge', 'version': '1.19.0'},
            'spans': otlp_spans,
        }]
    }]
}

print(json.dumps(payload, separators=(',', ':')))
" "$STATE_FILE" 2>/dev/null)

  # Handle empty telemetry gracefully
  if [[ -z "$otlp_json" ]]; then
    echo "WARNING: No telemetry spans to export"
    exit 0
  fi

  # POST to OTel collector
  local http_code
  http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$otlp_json" \
    "${ENDPOINT}/v1/traces" 2>/dev/null) || http_code="000"

  if [[ "$http_code" =~ ^2 ]]; then
    echo "OK: Telemetry exported (${http_code})"
    _update_export_status "exported"
  else
    echo "WARNING: OTel export failed (HTTP ${http_code}) — non-fatal, continuing"
    _update_export_status "failed"
    # Non-fatal: exit 0 per contract
  fi

  exit 0
}

# ── Helpers ──────────────────────────────────────────────────────────────

_update_export_status() {
  local status="$1"
  python3 -c "
import json, sys

state_file = sys.argv[1]
status = sys.argv[2]

try:
    with open(state_file) as f:
        state = json.load(f)
    if 'telemetry' in state:
        state['telemetry']['export_status'] = status
        with open(state_file, 'w') as f:
            json.dump(state, f, indent=2)
except Exception as e:
    print(f'WARNING: Could not update export_status: {e}', file=sys.stderr)
" "$STATE_FILE" "$status" 2>/dev/null || true
}

# ── Main dispatch ────────────────────────────────────────────────────────

case "$CMD" in
  export) do_export ;;
  check)  do_check ;;
  *)      echo "ERROR: unknown command: $CMD" >&2; exit 2 ;;
esac
