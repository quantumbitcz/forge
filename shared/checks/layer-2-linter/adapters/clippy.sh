#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: clippy (Rust linter via cargo)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: clippy.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v cargo &>/dev/null; then
  exit 1
fi

if [[ ! -f "$PROJECT_ROOT/Cargo.toml" ]]; then
  exit 1
fi

# --- run linter ---
RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

RC=0
(cd "$PROJECT_ROOT" && cargo clippy --message-format json 2>/dev/null) > "$RAW" || RC=$?

# clippy exits non-zero when findings exist — expected
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
clippy_map = full_map.get('clippy', {})

def lookup_severity(level, lint_group):
    # map via lint group first (e.g., 'correctness', 'perf', 'style')
    if lint_group in clippy_map:
        return clippy_map[lint_group]
    # fall back to compiler level
    level_map = {'error': 'CRITICAL', 'warning': 'WARNING', 'note': 'INFO', 'help': 'INFO'}
    return level_map.get(level, 'INFO')

def extract_lint_group(code_obj):
    \"\"\"Extract the clippy lint group from the code field.\"\"\"
    if not code_obj:
        return ''
    code_str = code_obj.get('code', '') if isinstance(code_obj, dict) else str(code_obj)
    # clippy lints look like 'clippy::lint_name'
    if 'clippy::' in code_str:
        return ''  # individual lint, check explanation for group
    return ''

def extract_group_from_explanation(code_obj):
    \"\"\"Try to extract the group from the code explanation field.\"\"\"
    if not code_obj or not isinstance(code_obj, dict):
        return ''
    explanation = code_obj.get('explanation', '')
    for group in ('correctness', 'suspicious', 'perf', 'style', 'nursery', 'complexity', 'pedantic'):
        if group in explanation.lower():
            return group
    return ''

def map_category(level, lint_name):
    if 'unsafe' in lint_name or 'security' in lint_name:
        return 'RS-LINT-SEC'
    if 'perf' in lint_name:
        return 'RS-LINT-PERF'
    if level == 'error':
        return 'RS-LINT-ERR'
    return 'RS-LINT-CLIPPY'

with open(raw_path) as f:
    for raw_line in f:
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        try:
            obj = json.loads(raw_line)
        except json.JSONDecodeError:
            continue

        if obj.get('reason') != 'compiler-message':
            continue

        msg = obj.get('message', {})
        if not msg:
            continue

        level = msg.get('level', 'warning')
        # skip notes/help that are sub-diagnostics
        if level in ('note', 'help'):
            continue

        text = msg.get('message', '').replace('|', '-')
        code_obj = msg.get('code')
        lint_name = ''
        if code_obj and isinstance(code_obj, dict):
            lint_name = code_obj.get('code', '')

        group = extract_group_from_explanation(code_obj)

        spans = msg.get('spans', [])
        if not spans:
            continue

        # use the primary span, or first span
        span = next((s for s in spans if s.get('is_primary')), spans[0])
        filepath = span.get('file_name', '?')
        line_start = span.get('line_start', 0)

        severity = lookup_severity(level, group)
        category = map_category(level, lint_name)
        hint = f'clippy lint {lint_name}' if lint_name else 'clippy warning'
        print(f'{filepath}:{line_start} | {category} | {severity} | {text} | {hint}')
" "$SEVERITY_MAP" "$RAW"

exit 0
