#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: dart analyze (Dart static analysis)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

# shellcheck disable=SC2034  # adapter interface contract
PROJECT_ROOT="${1:?usage: dart-analyzer.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v dart &>/dev/null; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
dart analyze --format=json "$TARGET" 2>/dev/null > "$RAW" || RC=$?

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
dart_map = full_map.get('dart', {})

def lookup_severity(code, dart_severity):
    if code in dart_map:
        return dart_map[code]
    best = ('', None)
    for pattern, sev in dart_map.items():
        prefix = pattern.rstrip('*')
        if code.startswith(prefix) and len(prefix) > len(best[0]):
            best = (prefix, sev)
    if best[1]:
        return best[1]
    mapping = {'ERROR': 'CRITICAL', 'WARNING': 'WARNING', 'INFO': 'INFO'}
    return mapping.get(dart_severity, 'INFO')

def map_category(code):
    if not code:
        return 'DART-LINT'
    if 'deprecated' in code.lower():
        return 'DART-LINT-DEPRECATION'
    if 'unused' in code.lower():
        return 'DART-LINT-UNUSED'
    return 'DART-LINT'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for diag in data.get('diagnostics', []):
    filepath = diag.get('location', {}).get('file', '?')
    row = diag.get('location', {}).get('range', {}).get('start', {}).get('line', 0)
    code = diag.get('code', '')
    message = diag.get('problemMessage', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
    dart_sev = diag.get('severity', 'INFO')
    severity = lookup_severity(code, dart_sev)
    category = map_category(code)
    hint = f'dart analyze: {code}' if code else 'dart analyze'
    print(f'{filepath}:{row} | {category} | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
