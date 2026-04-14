#!/usr/bin/env bash
# Context degradation guard for the forge pipeline.
#
# Commands:
#   check <estimated_tokens> [--forge-dir PATH]  -- Check context size, trigger condensation if needed
#   metrics [--forge-dir PATH]                    -- Report context metrics for this run
#
# Exit codes:
#   0 = OK (below threshold)
#   1 = CONDENSED (forced condensation, proceeding)
#   2 = CRITICAL (repeated exceedances, recommend task decomposition)
#   10 = disabled (context_guard.enabled is false)
#   11 = input error
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_WRITER="${SCRIPT_DIR}/forge-state-write.sh"

FORGE_DIR=".forge"
CMD=""
ESTIMATED_TOKENS=""

# Default thresholds (configurable via forge-config.md context_guard section)
CONDENSATION_THRESHOLD=30000
CRITICAL_THRESHOLD=50000
MAX_TRIGGERS=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    check)
      CMD="check"; shift
      ESTIMATED_TOKENS="${1:?check requires <estimated_tokens>}"; shift ;;
    metrics)
      CMD="metrics"; shift ;;
    --forge-dir)
      shift; FORGE_DIR="${1:?--forge-dir requires a path}"; shift ;;
    *)
      echo "ERROR: unknown argument: $1" >&2; exit 11 ;;
  esac
done

[[ -z "$CMD" ]] && { echo "Usage: context-guard.sh {check|metrics} ..." >&2; exit 11; }

_read_state() {
  bash "$STATE_WRITER" read --forge-dir "$FORGE_DIR"
}

_write_state_retry() {
  local _max_retries=5 _attempt=0 _updated="$1"
  while true; do
    bash "$STATE_WRITER" write "$_updated" --forge-dir "$FORGE_DIR" > /dev/null
    local _rc=$?
    if [[ $_rc -eq 0 ]]; then break
    elif [[ $_rc -eq 3 && $_attempt -lt $_max_retries ]]; then
      _attempt=$((_attempt + 1))
      sleep 0.1 2>/dev/null || true
      # Re-read and merge context section
      local _fresh_state
      _fresh_state=$(_read_state) || return 2
      _updated=$(python3 -c "
import json, sys
fresh = json.loads(sys.argv[1])
ours = json.loads(sys.argv[2])
if 'context' in ours:
    fresh['context'] = ours['context']
json.dump(fresh, sys.stdout)
" "$_fresh_state" "$_updated") || return 2
      continue
    else
      echo "ERROR: state write failed" >&2; return 2
    fi
  done
}

# ── Check ─────────────────────────────────────────────────────────────────

do_check() {
  local state_file="${FORGE_DIR}/state.json"
  [[ ! -f "$state_file" ]] && { echo "OK: no state.json"; exit 0; }

  local current_state
  current_state=$(_read_state) || { echo "OK: could not read state"; exit 0; }

  local result
  result=$(echo "$current_state" | python3 -c "
import json, sys, os

state = json.load(sys.stdin)
estimated = int(sys.argv[1])
cond_threshold = int(sys.argv[2])
crit_threshold = int(sys.argv[3])
max_triggers = int(sys.argv[4])

# Read config overrides
config_path = os.path.join(os.environ.get('FORGE_CONFIG_DIR', '.'), 'forge-config.md')
try:
    if os.path.exists(config_path):
        with open(config_path) as cf:
            content = cf.read()
        # Try yaml first, fall back to regex parsing
        cg = {}
        try:
            import yaml
            parts = content.split('---')
            if len(parts) >= 3:
                cfg = yaml.safe_load(parts[1]) or {}
                cg = cfg.get('context_guard', {})
        except ImportError:
            # No PyYAML — use regex fallback for simple key: value pairs
            import re
            in_cg = False
            for line in content.splitlines():
                if re.match(r'context_guard:', line):
                    in_cg = True
                    continue
                if in_cg and not line.startswith(' '):
                    break
                if in_cg:
                    m = re.match(r'\s+(\w+):\s*(.+)', line)
                    if m:
                        val = m.group(2).strip()
                        if val == 'false': val = False
                        elif val == 'true': val = True
                        elif val.isdigit(): val = int(val)
                        cg[m.group(1)] = val
        if cg.get('enabled') is False:
            print('EXIT:10')
            print('DISABLED')
            sys.exit(0)
        if 'condensation_threshold' in cg:
            cond_threshold = int(cg['condensation_threshold'])
        if 'critical_threshold' in cg:
            crit_threshold = int(cg['critical_threshold'])
        if 'max_condensation_triggers' in cg:
            max_triggers = int(cg['max_condensation_triggers'])
except Exception:
    pass

# Initialize context section if missing
ctx = state.get('context', {
    'peak_tokens': 0,
    'condensation_triggers': 0,
    'per_stage_peak': {},
    'last_estimated_tokens': 0,
    'guard_checks': 0,
})

# Update tracking
ctx['guard_checks'] = ctx.get('guard_checks', 0) + 1
ctx['last_estimated_tokens'] = estimated
if estimated > ctx.get('peak_tokens', 0):
    ctx['peak_tokens'] = estimated

# Track per-stage peak
current_stage = state.get('story_state', 'unknown').lower()
stage_peak = ctx.get('per_stage_peak', {}).get(current_stage, 0)
if estimated > stage_peak:
    ctx.setdefault('per_stage_peak', {})[current_stage] = estimated

# Determine exit code
if estimated >= crit_threshold:
    ctx['condensation_triggers'] = ctx.get('condensation_triggers', 0) + 1
    state['context'] = ctx
    print('STATE:' + json.dumps(state))
    if ctx['condensation_triggers'] >= max_triggers:
        print('EXIT:2')
        print(f'CRITICAL: context exceeded {crit_threshold} tokens {ctx[\"condensation_triggers\"]} times')
        print('Recommend breaking work into smaller tasks')
    else:
        print('EXIT:1')
        print(f'CONDENSED: context at {estimated} tokens (critical: {crit_threshold})')
elif estimated >= cond_threshold:
    ctx['condensation_triggers'] = ctx.get('condensation_triggers', 0) + 1
    state['context'] = ctx
    print('STATE:' + json.dumps(state))
    if ctx['condensation_triggers'] >= max_triggers:
        print('EXIT:2')
        print(f'CRITICAL: condensation triggered {ctx[\"condensation_triggers\"]} times this run')
        print('Recommend breaking work into smaller tasks')
    else:
        print('EXIT:1')
        print(f'CONDENSED: context at {estimated} tokens (threshold: {cond_threshold})')
else:
    state['context'] = ctx
    print('STATE:' + json.dumps(state))
    print('EXIT:0')
    print(f'OK: context at {estimated} tokens')
" "$ESTIMATED_TOKENS" "$CONDENSATION_THRESHOLD" "$CRITICAL_THRESHOLD" "$MAX_TRIGGERS")

  local exit_code=0
  local output_lines=()
  local updated_state=""

  while IFS= read -r line; do
    if [[ "$line" == "DISABLED" ]]; then
      exit 10
    elif [[ "$line" == EXIT:* ]]; then
      exit_code="${line#EXIT:}"
    elif [[ "$line" == STATE:* ]]; then
      updated_state="${line#STATE:}"
    else
      output_lines+=("$line")
    fi
  done <<< "$result"

  for line in "${output_lines[@]}"; do
    echo "$line"
  done

  if [[ -n "$updated_state" ]]; then
    _write_state_retry "$updated_state"
  fi

  exit "$exit_code"
}

# ── Metrics ───────────────────────────────────────────────────────────────

do_metrics() {
  local state_file="${FORGE_DIR}/state.json"
  [[ ! -f "$state_file" ]] && { echo "No context metrics available"; exit 0; }

  local current_state
  current_state=$(_read_state) || { echo "No context metrics available"; exit 0; }

  echo "$current_state" | python3 -c "
import json, sys
state = json.load(sys.stdin)
ctx = state.get('context', {})
print(f'peak_tokens: {ctx.get(\"peak_tokens\", 0)}')
print(f'condensation_triggers: {ctx.get(\"condensation_triggers\", 0)}')
print(f'last_estimated_tokens: {ctx.get(\"last_estimated_tokens\", 0)}')
print(f'guard_checks: {ctx.get(\"guard_checks\", 0)}')
stages = ctx.get('per_stage_peak', {})
if stages:
    print('per_stage_peak:')
    for s, v in stages.items():
        print(f'  {s}: {v}')
"
}

# ── Dispatch ──────────────────────────────────────────────────────────────

case "$CMD" in
  check)   do_check ;;
  metrics) do_metrics ;;
esac
