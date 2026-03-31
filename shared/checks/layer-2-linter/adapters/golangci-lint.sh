#!/usr/bin/env bash
set -euo pipefail
# Layer-2 adapter: golangci-lint
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: golangci-lint.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

command -v golangci-lint &>/dev/null || exit 1

RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX"); trap 'rm -f "$RAW"' EXIT

RC=0
(cd "$PROJECT_ROOT" && golangci-lint run --out-format json "$TARGET" 2>/dev/null) > "$RAW" || RC=$?

# golangci-lint exits 1 when issues found — expected
# exit 2 only on real errors (empty output with non-zero exit)
[[ $RC -gt 1 ]] && exit 2
[[ $RC -ne 0 && ! -s "$RAW" ]] && exit 2

# --- parse findings ---
python3 -c "
import json, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
gl_map = full_map.get('golangci-lint', {})

def lookup_severity(linter, text):
    if linter and linter in gl_map:
        return gl_map[linter]
    t = (text or '').lower()
    if any(w in t for w in ('error', 'undefined', 'cannot', 'illegal')):
        return 'CRITICAL'
    if any(w in t for w in ('should', 'consider', 'unused', 'shadow')):
        return 'WARNING'
    return 'INFO'

def map_category(linter):
    if not linter: return 'GO-LINT'
    l = linter.lower()
    if l in ('errcheck', 'errorlint'): return 'GO-LINT-ERR'
    if l in ('gosec', 'gas'): return 'GO-SEC'
    if l in ('govet', 'vet'): return 'GO-LINT-VET'
    if l in ('staticcheck', 'stylecheck'): return 'GO-LINT-SA'
    if l in ('revive', 'golint'): return 'GO-LINT-STYLE'
    if l in ('unused', 'deadcode', 'structcheck', 'varcheck'): return 'GO-LINT-UNUSED'
    if l in ('bodyclose', 'noctx'): return 'GO-LINT-PERF'
    return 'GO-LINT'

with open(raw_path) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        sys.exit(0)

for issue in data.get('Issues') or []:
    pos = issue.get('Pos', {})
    fp = pos.get('Filename', '?')
    ln = pos.get('Line', 0)
    linter = issue.get('FromLinter', '')
    text = issue.get('Text', '').replace('|', '\\\\|')
    severity = lookup_severity(linter, text)
    category = map_category(linter)
    hint = f'golangci-lint/{linter}' if linter else 'golangci-lint'
    print(f'{fp}:{ln} | {category} | {severity} | {text} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
