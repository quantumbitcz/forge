#!/usr/bin/env bash
set -euo pipefail
# Layer-2 adapter: checkstyle (Java static analysis)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: checkstyle.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

HAS_GRADLE=false; HAS_CLI=false
[[ -f "$PROJECT_ROOT/gradlew" ]] && grep -qE 'checkstyle|java' "$PROJECT_ROOT/build.gradle" 2>/dev/null && HAS_GRADLE=true
command -v checkstyle &>/dev/null && HAS_CLI=true
[[ "$HAS_GRADLE" == false && "$HAS_CLI" == false ]] && exit 1

RAW=$(mktemp); trap 'rm -f "$RAW"' EXIT
RC=0
if [[ "$HAS_GRADLE" == true ]]; then
  (cd "$PROJECT_ROOT" && ./gradlew checkstyleMain -q 2>/dev/null) > "$RAW" || RC=$?
else
  checkstyle -f plain "$TARGET" 2>/dev/null > "$RAW" || RC=$?
fi
[[ $RC -ne 0 && ! -s "$RAW" ]] && exit 2

# --- parse findings ---
python3 -c "
import json, re, sys
with open(sys.argv[1]) as f: full_map = json.load(f)
cs_map = full_map.get('checkstyle', {})

def lookup_sev(cs_sev): return cs_map.get(cs_sev.upper(), 'INFO')

def map_cat(msg):
    m = msg.lower()
    if any(k in m for k in ('javadoc','comment')): return 'JV-LINT-DOC'
    if any(k in m for k in ('import','unused')): return 'JV-LINT-IMPORT'
    if any(k in m for k in ('whitespace','indent','spacing')): return 'JV-LINT-FORMAT'
    if any(k in m for k in ('naming','name','abbreviation')): return 'JV-LINT-NAMING'
    return 'JV-LINT-STYLE'

pat_plain = re.compile(r'^\[(ERROR|WARNING|INFO)]\s+(.+?):(\d+)(?::\d+)?:\s+(.+)$')
pat_alt = re.compile(r'^(.+?):(\d+)(?::\d+)?:\s+(.+)$')
with open(sys.argv[2]) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('Starting'): continue
        m = pat_plain.match(line)
        if m:
            cs_sev, fp, ln, msg = m.groups()
            print(f'{fp}:{ln} | {map_cat(msg)} | {lookup_sev(cs_sev)} | {msg} | checkstyle')
            continue
        m = pat_alt.match(line)
        if m:
            fp, ln, msg = m.groups()
            print(f'{fp}:{ln} | {map_cat(msg)} | INFO | {msg} | checkstyle')
" "$SEVERITY_MAP" "$RAW"
exit 0
