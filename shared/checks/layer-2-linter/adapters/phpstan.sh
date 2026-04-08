#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: phpstan (PHP static analysis)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

# shellcheck disable=SC2034  # adapter interface contract
PROJECT_ROOT="${1:?usage: phpstan.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v phpstan &>/dev/null; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
phpstan analyse --error-format=json --no-progress "$TARGET" 2>/dev/null > "$RAW" || RC=$?

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
phpstan_map = full_map.get('phpstan', {})

def lookup_severity(identifier):
    if identifier in phpstan_map:
        return phpstan_map[identifier]
    best = ('', 'WARNING')
    for pattern, sev in phpstan_map.items():
        prefix = pattern.rstrip('*')
        if identifier.startswith(prefix) and len(prefix) > len(best[0]):
            best = (prefix, sev)
    return best[1]

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for filepath, errors in data.get('files', {}).items():
    for err in errors.get('messages', []):
        row = err.get('line', 0)
        message = err.get('message', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
        identifier = err.get('identifier', '')
        severity = lookup_severity(identifier)
        category = 'PHP-LINT-PHPSTAN'
        hint = f'phpstan: {identifier}' if identifier else 'phpstan analyse'
        print(f'{filepath}:{row} | {category} | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
