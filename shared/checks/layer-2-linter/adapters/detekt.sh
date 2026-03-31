#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: detekt (Kotlin static analysis)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: detekt.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
HAS_GRADLE=false
HAS_DETEKT_CLI=false

if [[ -f "$PROJECT_ROOT/gradlew" ]] && grep -q 'detekt' "$PROJECT_ROOT/build.gradle.kts" 2>/dev/null; then
  HAS_GRADLE=true
fi
if command -v detekt &>/dev/null; then
  HAS_DETEKT_CLI=true
fi

if [[ "$HAS_GRADLE" == false && "$HAS_DETEKT_CLI" == false ]]; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
if [[ "$HAS_GRADLE" == true ]]; then
  (cd "$PROJECT_ROOT" && ./gradlew detekt --no-daemon -q 2>/dev/null) > "$RAW" || RC=$?
else
  detekt --input "$TARGET" 2>/dev/null > "$RAW" || RC=$?
fi

# detekt exits non-zero when findings exist — that is expected
# Only exit 2 if the output file is empty AND RC is non-zero (real error)
if [[ $RC -ne 0 && ! -s "$RAW" ]]; then
  exit 2
fi

# --- parse findings ---
python3 -c "
import json, re, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
detekt_map = full_map.get('detekt', {})

def lookup_severity(rule_id):
    # exact match first
    if rule_id in detekt_map:
        return detekt_map[rule_id]
    # glob prefix match (longest wins)
    best = ('', 'INFO')
    for pattern, sev in detekt_map.items():
        if pattern.endswith('.*'):
            prefix = pattern[:-2]
            if rule_id.startswith(prefix) and len(prefix) > len(best[0]):
                best = (prefix, sev)
        elif pattern.endswith('*'):
            prefix = pattern[:-1]
            if rule_id.startswith(prefix) and len(prefix) > len(best[0]):
                best = (prefix, sev)
    return best[1]

def map_category(rule_id):
    rule_lower = rule_id.lower()
    if any(k in rule_lower for k in ('security', 'injection', 'eval')):
        return 'SEC-DETEKT'
    if any(k in rule_lower for k in ('performance', 'perf')):
        return 'PERF-DETEKT'
    if any(k in rule_lower for k in ('exception', 'error', 'swallow')):
        return 'QUAL-ERR'
    if any(k in rule_lower for k in ('complexity', 'long', 'large')):
        return 'QUAL-COMPLEX'
    return 'QUAL-DETEKT'

# detekt format: path/file.kt:line:col: description [RuleId]
pat = re.compile(r'^(.+?):(\d+):\d+:\s+(.+?)\s+\[([\w.]+)]')

with open(raw_path) as f:
    for line in f:
        m = pat.match(line.strip())
        if not m:
            continue
        filepath, lineno, message, rule_id = m.group(1), m.group(2), m.group(3), m.group(4)
        # Escape pipe characters per output-format.md
        message = message.replace('|', '\\|')
        severity = lookup_severity(rule_id)
        category = map_category(rule_id)
        hint = f'detekt rule {rule_id}'
        print(f'{filepath}:{lineno} | {category} | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
