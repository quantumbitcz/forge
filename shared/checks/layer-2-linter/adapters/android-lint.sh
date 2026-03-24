#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: Android Lint + detekt (Android/Compose projects)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: android-lint.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
HAS_GRADLEW=false
if [[ -f "$PROJECT_ROOT/gradlew" ]]; then
  HAS_GRADLEW=true
fi

if [[ "$HAS_GRADLEW" == false ]]; then
  exit 1
fi

# --- run linters ---
RAW_LINT=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
RAW_DETEKT=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW_LINT" "$RAW_DETEKT"' EXIT

# Run Android Lint (XML output for machine parsing)
RC_LINT=0
(cd "$PROJECT_ROOT" && ./gradlew lintDebug --no-daemon -q 2>/dev/null) || RC_LINT=$?

# Find the most recent lint XML report
LINT_REPORT=$(find "$PROJECT_ROOT" -name "lint-results*.xml" -newer "$PROJECT_ROOT/gradlew" 2>/dev/null | head -1)

# Run detekt if configured
RC_DETEKT=0
if grep -q 'detekt' "$PROJECT_ROOT/build.gradle.kts" 2>/dev/null || \
   grep -rq 'detekt' "$PROJECT_ROOT/app/build.gradle.kts" 2>/dev/null; then
  (cd "$PROJECT_ROOT" && ./gradlew detekt --no-daemon -q 2>/dev/null) > "$RAW_DETEKT" || RC_DETEKT=$?
fi

# --- parse findings ---
python3 -c "
import json, re, sys, os
from xml.etree import ElementTree as ET

sev_map_path = sys.argv[1]
lint_report  = sys.argv[2]
detekt_raw   = sys.argv[3]

with open(sev_map_path) as f:
    full_map = json.load(f)
android_map = full_map.get('android_lint', {})
detekt_map  = full_map.get('detekt', {})

def map_lint_severity(lint_sev, issue_id):
    if issue_id in android_map:
        return android_map[issue_id]
    return {'Fatal': 'CRITICAL', 'Error': 'WARNING', 'Warning': 'WARNING', 'Information': 'INFO'}.get(lint_sev, 'INFO')

def map_lint_category(category):
    cat = category.lower()
    if 'security' in cat:  return 'SEC-LINT'
    if 'performance' in cat: return 'PERF-LINT'
    if 'accessibility' in cat: return 'A11Y-LINT'
    if 'correctness' in cat: return 'QUAL-LINT'
    if 'usability' in cat: return 'QUAL-LINT'
    return 'ANDROID-LINT'

def map_detekt_severity(rule_id):
    if rule_id in detekt_map:
        return detekt_map[rule_id]
    rule_lower = rule_id.lower()
    if any(k in rule_lower for k in ('security', 'injection')):   return 'WARNING'
    if any(k in rule_lower for k in ('complexity', 'long')):      return 'INFO'
    return 'INFO'

# Parse Android Lint XML report
if lint_report and os.path.isfile(lint_report):
    try:
        tree = ET.parse(lint_report)
        root = tree.getroot()
        for issue in root.findall('.//issue'):
            issue_id  = issue.get('id', 'unknown')
            lint_sev  = issue.get('severity', 'Warning')
            summary   = issue.get('summary', '').replace('|', '-')
            category  = issue.get('category', 'Correctness')
            for loc in issue.findall('location'):
                filepath = loc.get('file', '?')
                line     = loc.get('line', '0')
                severity = map_lint_severity(lint_sev, issue_id)
                cat      = map_lint_category(category)
                hint     = f'android lint [{issue_id}]'
                print(f'{filepath}:{line} | {cat} | {severity} | {summary} | {hint}')
    except ET.ParseError:
        pass

# Parse detekt output
pat = re.compile(r'^(.+?):(\d+):\d+:\s+(.+?)\s+\[([\w.]+)]')
with open(detekt_raw) as f:
    for line in f:
        m = pat.match(line.strip())
        if not m:
            continue
        filepath, lineno, message, rule_id = m.group(1), m.group(2), m.group(3), m.group(4)
        severity = map_detekt_severity(rule_id)
        hint     = f'detekt rule {rule_id}'
        print(f'{filepath}:{lineno} | QUAL-DETEKT | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "${LINT_REPORT:-/dev/null}" "$RAW_DETEKT"

exit 0
