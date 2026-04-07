#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: ESLint (JavaScript/TypeScript)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: eslint.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! (cd "$PROJECT_ROOT" && npx eslint --version &>/dev/null); then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
(cd "$PROJECT_ROOT" && npx eslint --format json "$TARGET" 2>/dev/null) > "$RAW" || RC=$?

# eslint exits 1 when findings exist — expected
# exit 2 only on real errors (empty output with non-zero)
if [[ $RC -gt 1 ]]; then
  exit 2
fi
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
eslint_map = full_map.get('eslint', {})
eslint_sev_map = eslint_map.get('_severity_map', {})

def lookup_severity(rule_id, eslint_severity):
    # exact rule match first
    if rule_id and rule_id in eslint_map:
        return eslint_map[rule_id]
    # fall back to eslint severity number → string → mapped severity
    sev_str = {2: 'error', 1: 'warn'}.get(eslint_severity, 'warn')
    return eslint_sev_map.get(sev_str, 'INFO')

def map_category(rule_id):
    if not rule_id:
        return 'TS-LINT-PARSE'
    r = rule_id.lower()
    if 'eval' in r or 'script' in r:
        return 'SEC-EVAL'
    if 'security' in r or 'xss' in r:
        return 'SEC-ESLINT'
    if 'react-hooks' in r or 'react/' in r:
        return 'TS-LINT-REACT'
    if 'typescript' in r or '@typescript' in r:
        return 'TS-LINT-TS'
    if 'import' in r:
        return 'TS-LINT-IMPORT'
    return 'TS-LINT-ESLINT'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        results = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

project_root = sys.argv[3] if len(sys.argv) > 3 else ''

for entry in results:
    filepath = entry.get('filePath', '?')
    # Convert absolute paths to project-relative per output-format.md
    if project_root and filepath.startswith(project_root):
        filepath = filepath[len(project_root):].lstrip('/')
    for msg in entry.get('messages', []):
        line = msg.get('line', 0)
        rule_id = msg.get('ruleId', '')
        eslint_sev = msg.get('severity', 1)
        # Escape pipe characters per output-format.md (use \\| not replacement)
        message = msg.get('message', '').replace('|', '\\\\|')
        severity = lookup_severity(rule_id, eslint_sev)
        category = map_category(rule_id)
        hint = f'eslint rule {rule_id}' if rule_id else 'eslint parse error'
        print(f'{filepath}:{line} | {category} | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "$RAW" "$PROJECT_ROOT"

exit 0
