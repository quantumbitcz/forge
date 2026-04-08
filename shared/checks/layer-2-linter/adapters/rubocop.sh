#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: rubocop (Ruby linter)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

# shellcheck disable=SC2034  # adapter interface contract
PROJECT_ROOT="${1:?usage: rubocop.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v rubocop &>/dev/null; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
rubocop --format json "$TARGET" 2>/dev/null > "$RAW" || RC=$?

# rubocop exits 1 when findings exist — expected
if [[ $RC -ne 0 && ! -s "$RAW" ]]; then
  exit 2
fi

# --- parse findings ---
_PY="python3"; command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then exit 0; fi
"$_PY" -c "
import json, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
rubocop_map = full_map.get('rubocop', {})

def lookup_severity(rb_severity, cop_name):
    # Check cop-specific override first (e.g., 'Security/*': 'CRITICAL')
    if cop_name in rubocop_map:
        return rubocop_map[cop_name]
    best_cop = ('', '')
    for pattern, sev in rubocop_map.items():
        prefix = pattern.rstrip('*')
        if cop_name.startswith(prefix) and len(prefix) > len(best_cop[0]):
            best_cop = (prefix, sev)
    if best_cop[1]:
        return best_cop[1]
    # Fall back to RuboCop severity level (Fatal, Error, Warning, Convention, Refactor)
    cap = rb_severity.capitalize() if rb_severity else ''
    return rubocop_map.get(cap, 'INFO')

def map_category(cop_name):
    if not cop_name:
        return 'RB-LINT-RUBOCOP'
    parts = cop_name.split('/')
    dept = parts[0] if parts else ''
    if dept == 'Security':
        return 'RB-LINT-SEC'
    if dept == 'Performance':
        return 'RB-LINT-PERF'
    if dept in ('Layout', 'Style'):
        return 'RB-LINT-STYLE'
    if dept == 'Lint':
        return 'RB-LINT-BUG'
    if dept == 'Metrics':
        return 'RB-LINT-METRICS'
    return 'RB-LINT-RUBOCOP'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for file_entry in data.get('files', []):
    path = file_entry.get('path', '?')
    for offense in file_entry.get('offenses', []):
        loc = offense.get('location', {})
        row = loc.get('start_line', 0)
        cop = offense.get('cop_name', '')
        rb_severity = offense.get('severity', '')
        message = offense.get('message', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
        severity = lookup_severity(rb_severity, cop)
        category = map_category(cop)
        hint = f'rubocop cop {cop}' if cop else 'rubocop'
        print(f'{path}:{row} | {category} | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
