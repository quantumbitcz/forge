#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: hadolint (Dockerfile linter)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

# shellcheck disable=SC2034  # adapter interface contract
PROJECT_ROOT="${1:?usage: hadolint.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v hadolint &>/dev/null; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
hadolint --format json "$TARGET" 2>/dev/null > "$RAW" || RC=$?

# hadolint exits 1 when findings exist — expected
if [[ $RC -ne 0 && ! -s "$RAW" ]]; then
  exit 2
fi

# --- parse findings ---
_PY="python3"
command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then
  exit 0
fi

"$_PY" -c "
import json, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]
target = sys.argv[3]

with open(sev_map_path) as f:
    full_map = json.load(f)
hadolint_map = full_map.get('hadolint', {})

def lookup_severity(level, code):
    # exact code match first
    if code in hadolint_map:
        return hadolint_map[code]
    # severity level map
    sev_map = hadolint_map.get('_severity_map', {})
    if level in sev_map:
        return sev_map[level]
    # default mapping
    level_lower = level.lower() if level else ''
    if level_lower == 'error':
        return 'WARNING'
    if level_lower == 'warning':
        return 'INFO'
    return 'INFO'

def map_category(code):
    if not code:
        return 'DF-LINT'
    c = code.upper()
    if c.startswith('DL'):
        num = int(c[2:]) if c[2:].isdigit() else 0
        # DL3002 (last user = root) is security; rest of DL3xxx are best practices
        if c == 'DL3002':
            return 'DF-LINT-SEC'
        if 3000 <= num < 5000:
            return 'DF-LINT-BEST'
    if c.startswith('SC'):
        return 'DF-LINT-SHELL'
    return 'DF-LINT'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        findings = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for item in findings:
    line = item.get('line', 0)
    code = item.get('code', '')
    message = item.get('message', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
    level = item.get('level', 'warning')
    severity = lookup_severity(level, code)
    category = map_category(code)
    hint = f'hadolint rule {code}' if code else 'hadolint check'
    print(f'{target}:{line} | {category} | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "$RAW" "$TARGET"

exit 0
