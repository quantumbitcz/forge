#!/usr/bin/env bash
set -euo pipefail
# Layer-2 adapter: clang-tidy (C/C++ static analysis)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: clang-tidy.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

command -v clang-tidy &>/dev/null || exit 1

RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX"); trap 'rm -f "$RAW"' EXIT
EXTRA_ARGS=()
[[ -f "$PROJECT_ROOT/compile_commands.json" ]] && EXTRA_ARGS+=(-p "$PROJECT_ROOT")

RC=0
clang-tidy "${EXTRA_ARGS[@]}" "$TARGET" 2>/dev/null > "$RAW" || RC=$?
[[ $RC -ne 0 && ! -s "$RAW" ]] && exit 2

# --- parse findings ---
_PY="python3"; command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then exit 0; fi
"$_PY" -c "
import json, re, sys
with open(sys.argv[1]) as f: full_map = json.load(f)
ct_map = full_map.get('clang-tidy', {})

def lookup_sev(check, diag_sev):
    best = ('', None)
    for pat, sev in ct_map.items():
        if pat.endswith('*'):
            px = pat[:-1]
            if check.startswith(px) and len(px) > len(best[0]): best = (px, sev)
    return best[1] if best[1] else ct_map.get(diag_sev, 'INFO')

CAT_PREFIX = {'bugprone':'C-LINT-BUGPRONE','cert':'C-LINT-CERT','security':'C-LINT-SECURITY',
              'modernize':'C-LINT-MODERNIZE','performance':'C-LINT-PERF','readability':'C-LINT-READABILITY'}
def map_cat(check):
    for px, cat in CAT_PREFIX.items():
        if check.startswith(px): return cat
    return 'C-LINT-TIDY'

pat = re.compile(r'^(.+?):(\d+):\d+:\s+(warning|error|note):\s+(.+?)\s+\[([^\]]+)\]\s*$')
with open(sys.argv[2]) as f:
    for line in f:
        m = pat.match(line.strip())
        if not m: continue
        fp, ln, diag_sev, msg, check = m.groups()
        if diag_sev == 'note': continue
        msg = msg.replace('|', '\\\\|')
        print(f'{fp}:{ln} | {map_cat(check)} | {lookup_sev(check, diag_sev)} | {msg} | clang-tidy [{check}]')
" "$SEVERITY_MAP" "$RAW"
exit 0
