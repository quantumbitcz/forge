#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: swiftlint (Swift static analysis)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: swiftlint.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
command -v swiftlint &>/dev/null || exit 1

# --- run linter ---
RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

RC=0
swiftlint lint --path "$TARGET" --reporter json 2>/dev/null > "$RAW" || RC=$?

# Non-zero exit with findings is expected; empty output + error is real failure
if [[ $RC -ne 0 && ! -s "$RAW" ]]; then
  exit 2
fi

# --- parse findings ---
python3 -c "
import json, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
sl_map = full_map.get('swiftlint', {})

def lookup_severity(swift_sev, rule_id):
    return sl_map.get(swift_sev, 'INFO')

def map_category(rule_id):
    rule = rule_id.lower()
    if any(k in rule for k in ('force_cast', 'force_try', 'force_unwrap')):
        return 'SW-LINT-SAFETY'
    if any(k in rule for k in ('complexity', 'length', 'size')):
        return 'SW-LINT-COMPLEX'
    if any(k in rule for k in ('unused', 'redundant')):
        return 'SW-LINT-CLEAN'
    return 'SW-LINT-STYLE'

with open(raw_path) as f:
    try:
        findings = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)

if not isinstance(findings, list):
    sys.exit(0)

for item in findings:
    fp = item.get('file', '?')
    ln = item.get('line', 0)
    reason = item.get('reason', '')
    rule_id = item.get('rule_id', '')
    swift_sev = item.get('severity', 'warning').lower()

    severity = lookup_severity(swift_sev, rule_id)
    category = map_category(rule_id)
    print(f'{fp}:{ln} | {category} | {severity} | {reason} | swiftlint [{rule_id}]')
" "$SEVERITY_MAP" "$RAW"

exit 0
