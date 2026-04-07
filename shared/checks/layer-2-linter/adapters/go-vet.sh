#!/usr/bin/env bash
set -euo pipefail
# Layer-2 adapter: go vet / staticcheck
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: go-vet.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

command -v go &>/dev/null || exit 1
HAS_SC=false; command -v staticcheck &>/dev/null && HAS_SC=true

RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX"); trap 'rm -f "$RAW"' EXIT
RC=0
if [[ "$HAS_SC" == true ]]; then
  (cd "$PROJECT_ROOT" && staticcheck ./... 2>&1) > "$RAW" || RC=$?
else
  (cd "$PROJECT_ROOT" && go vet ./... 2>&1) > "$RAW" || RC=$?
fi
[[ $RC -ne 0 && ! -s "$RAW" ]] && exit 2

# --- parse findings ---
_PY="python3"; command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then exit 0; fi
"$_PY" -c "
import json, re, sys
with open(sys.argv[1]) as f: full_map = json.load(f)
sc_map = full_map.get('staticcheck', {})

def lookup_sev(code):
    if not code: return 'WARNING'
    if code in sc_map: return sc_map[code]
    best = ('', 'WARNING')
    for pat, sev in sc_map.items():
        if pat.endswith('*'):
            px = pat[:-1]
            if code.startswith(px) and len(px) > len(best[0]): best = (px, sev)
    return best[1]

CAT_PREFIX = {'SA':'GO-LINT-SA','S1':'GO-LINT-SIMPLIFY','ST':'GO-LINT-STYLE','QF':'GO-LINT-QUICKFIX'}
def map_cat(code):
    if code:
        for px, cat in CAT_PREFIX.items():
            if code.startswith(px): return cat
    return 'GO-LINT-VET'

pat_sc = re.compile(r'^(.+?):(\d+):\d+:\s+(.+?)\s+\((\w+)\)\s*$')
pat_vet = re.compile(r'^(.+?):(\d+):\d+:\s+(.+)$')
with open(sys.argv[2]) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        m = pat_sc.match(line)
        if m:
            fp, ln, msg, code = m.groups()
            msg = msg.replace('|', '\\\\|')
            print(f'{fp}:{ln} | {map_cat(code)} | {lookup_sev(code)} | {msg} | staticcheck {code}')
            continue
        m = pat_vet.match(line)
        if m:
            fp, ln, msg = m.groups()
            msg = msg.replace('|', '\\\\|')
            print(f'{fp}:{ln} | GO-LINT-VET | WARNING | {msg} | go vet')
" "$SEVERITY_MAP" "$RAW"
exit 0
