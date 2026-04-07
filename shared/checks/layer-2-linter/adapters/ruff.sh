#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: ruff (Python linter)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: ruff.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v ruff &>/dev/null; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
ruff check --output-format json "$TARGET" 2>/dev/null > "$RAW" || RC=$?

# ruff exits 1 when findings exist — expected
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
ruff_map = full_map.get('ruff', {})

def lookup_severity(code):
    # exact match first
    if code in ruff_map:
        return ruff_map[code]
    # glob prefix match (longest wins)
    best = ('', 'INFO')
    for pattern, sev in ruff_map.items():
        prefix = pattern.rstrip('*')
        if code.startswith(prefix) and len(prefix) > len(best[0]):
            best = (prefix, sev)
    return best[1]

def map_category(code):
    if not code:
        return 'PY-LINT-RUFF'
    c = code.upper()
    if c.startswith('S'):
        return 'PY-LINT-SEC'
    if c.startswith('ASYNC'):
        return 'PY-LINT-ASYNC'
    if c.startswith('F'):
        return 'PY-LINT-PYFLAKES'
    if c.startswith('E') or c.startswith('W'):
        return 'PY-LINT-STYLE'
    if c.startswith('UP'):
        return 'PY-LINT-UPGRADE'
    if c.startswith('B'):
        return 'PY-LINT-BUGBEAR'
    return 'PY-LINT-RUFF'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        findings = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for item in findings:
    filename = item.get('filename', '?')
    loc = item.get('location', {})
    row = loc.get('row', 0)
    code = item.get('code', '')
    message = item.get('message', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
    severity = lookup_severity(code)
    category = map_category(code)
    hint = f'ruff rule {code}' if code else 'ruff check'
    print(f'{filename}:{row} | {category} | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
