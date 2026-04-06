#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: yamllint (YAML linter)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: yamllint.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v yamllint &>/dev/null; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
yamllint --format parsable "$TARGET" 2>/dev/null > "$RAW" || RC=$?

# yamllint exits 1 when findings exist — expected
if [[ $RC -ne 0 && ! -s "$RAW" ]]; then
  exit 2
fi

# --- parse findings ---
# yamllint parsable format: file:line:col: [level] message (rule)
_PY="python3"
command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then
  exit 0
fi

"$_PY" -c "
import json, sys, re

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
yamllint_map = full_map.get('yamllint', {})

def lookup_severity(level):
    sev_map = yamllint_map.get('_severity_map', {})
    if level in sev_map:
        return sev_map[level]
    if level == 'error':
        return 'WARNING'
    return 'INFO'

# parsable format: file:line:col: [level] message (rule)
pattern = re.compile(r'^(.+?):(\d+):\d+: \[(\w+)\] (.+?)(?:\s+\((\S+)\))?\$')

with open(raw_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        m = pattern.match(line)
        if not m:
            continue
        filepath, lineno, level, message, rule = m.groups()
        rule = rule or 'general'
        severity = lookup_severity(level)
        safe_msg = message.replace('|', '\\\\|')
        hint = f'yamllint rule: {rule}'
        print(f'{filepath}:{lineno} | YML-LINT | {severity} | {safe_msg} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
