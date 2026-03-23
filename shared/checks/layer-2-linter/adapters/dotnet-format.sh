#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: dotnet format (C#/.NET)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: dotnet-format.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v dotnet &>/dev/null; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

RC=0
(cd "$PROJECT_ROOT" && dotnet format --verify-no-changes --diagnostics 2>&1) > "$RAW" || RC=$?

# dotnet format exits 2 when formatting issues exist — expected
# exit 1 on other errors
if [[ $RC -ne 0 && $RC -ne 2 && ! -s "$RAW" ]]; then
  exit 2
fi

# --- parse findings ---
# dotnet format output contains lines like:
#   /path/file.cs(42,5): warning IDE0060: Remove unused parameter 'x'
#   /path/file.cs(10,1): error CS0168: The variable 'e' is declared but never used
python3 -c "
import json, sys, re

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
dotnet_map = full_map.get('dotnet-format', {})
dotnet_sev_map = dotnet_map.get('_severity_map', {})

def lookup_severity(diag_id, raw_severity):
    if diag_id and diag_id in dotnet_map:
        return dotnet_map[diag_id]
    return dotnet_sev_map.get(raw_severity, 'INFO')

def map_category(diag_id):
    if not diag_id:
        return 'CS-LINT-PARSE'
    d = diag_id.upper()
    if d.startswith('IDE'):
        return 'CS-LINT-IDE'
    if d.startswith('CS'):
        return 'CS-LINT-COMPILER'
    if d.startswith('CA'):
        return 'CS-LINT-ANALYSIS'
    if d.startswith('SA') or d.startswith('SCS'):
        return 'SEC-DOTNET'
    return 'CS-LINT-OTHER'

# Pattern: file(line,col): severity DIAGID: message
pattern = re.compile(r'^(.+?)\((\d+),\d+\):\s+(warning|error|info)\s+(\w+):\s+(.+)$')

with open(raw_path) as f:
    for line in f:
        line = line.strip()
        m = pattern.match(line)
        if not m:
            continue
        filepath, line_no, raw_sev, diag_id, message = m.groups()
        severity = lookup_severity(diag_id, raw_sev)
        category = map_category(diag_id)
        message = message.replace('|', '-')
        hint = f'dotnet diagnostic {diag_id}'
        print(f'{filepath}:{line_no} | {category} | {severity} | {message} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
