#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: credo (Elixir linter)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: credo.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v mix &>/dev/null; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
(cd "$PROJECT_ROOT" && mix credo --format json --files-included "$TARGET" 2>/dev/null > "$RAW") || RC=$?

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
credo_map = full_map.get('credo', {})

def lookup_severity(check):
    if check in credo_map:
        return credo_map[check]
    best = ('', 'INFO')
    for pattern, sev in credo_map.items():
        prefix = pattern.rstrip('*')
        if check.startswith(prefix) and len(prefix) > len(best[0]):
            best = (prefix, sev)
    return best[1]

def map_category(check, priority):
    if not check:
        return 'EX-LINT-CREDO'
    if 'Security' in check or 'Warning' in check:
        return 'EX-LINT-SEC'
    if 'Readability' in check:
        return 'EX-LINT-STYLE'
    if 'Refactor' in check:
        return 'EX-LINT-REFACTOR'
    if 'Design' in check:
        return 'EX-LINT-DESIGN'
    if 'Consistency' in check:
        return 'EX-LINT-CONSISTENCY'
    return 'EX-LINT-CREDO'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for issue in data.get('issues', []):
    filepath = issue.get('filename', '?')
    row = issue.get('line_no', 0)
    check = issue.get('check', '')
    message = issue.get('message', '').replace('|', '\\\\|')
    priority = issue.get('priority', 0)
    severity = lookup_severity(check)
    category = map_category(check, priority)
    hint = f'credo: {check}' if check else 'mix credo'
    print(f'{filepath}:{row} | {category} | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
