#!/usr/bin/env bash
# Per-section config change detection for forge-config.md.
# Compares current config against previous run's per-section hashes
# stored in .forge/config-hashes.json. Used by the orchestrator at
# PREFLIGHT and by the retrospective for audit.
#
# Usage:
#   ./shared/config-diff.sh <project-root>           # Print diff report
#   ./shared/config-diff.sh --snapshot <project-root> # Save current hashes (no diff)
#   ./shared/config-diff.sh --json <project-root>     # Output JSON diff
#
# Exit codes:
#   0 — no changes (or snapshot saved)
#   1 — changes detected
#   2 — error (missing files, parse failure)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source platform helpers
# shellcheck source=platform.sh
source "${SCRIPT_DIR}/platform.sh"

# ── Globals ─────────────────────────────────────────────────────────────────

SNAPSHOT_ONLY=false
JSON_OUTPUT=false
PROJECT_ROOT=""

# ── Argument parsing ────────────────────────────────────────────────────────

usage() {
  echo "Usage: config-diff.sh [--snapshot] [--json] <project-root>"
  echo ""
  echo "Tracks per-section changes to forge-config.md across pipeline runs."
  echo ""
  echo "Options:"
  echo "  --snapshot  Save current section hashes without diffing"
  echo "  --json      Output changes as JSON"
  echo ""
  echo "Exit codes:"
  echo "  0 — no changes (or snapshot saved)"
  echo "  1 — changes detected"
  echo "  2 — error"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --snapshot)  SNAPSHOT_ONLY=true; shift ;;
    --json)      JSON_OUTPUT=true; shift ;;
    --help|-h)   usage; exit 0 ;;
    -*)          echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)           PROJECT_ROOT="$1"; shift ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo "ERROR: project-root argument is required" >&2
  usage >&2
  exit 2
fi

CONFIG_FILE="${PROJECT_ROOT}/.claude/forge-config.md"
FORGE_DIR="${PROJECT_ROOT}/.forge"
HASHES_FILE="${FORGE_DIR}/config-hashes.json"

# ── Prerequisite check ─────────────────────────────────────────────────────

if [[ -z "$FORGE_PYTHON" ]]; then
  echo "ERROR: python3 is required for config-diff" >&2
  exit 2
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: forge-config.md not found at ${CONFIG_FILE}" >&2
  exit 2
fi

# Ensure .forge/ exists
mkdir -p "$FORGE_DIR"

# ── Extract YAML from markdown ─────────────────────────────────────────────

extract_yaml() {
  local file="$1"
  "$FORGE_PYTHON" -c "
import sys, re

content = open(sys.argv[1]).read()

# Strategy 1: YAML frontmatter between --- delimiters
fm = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if fm:
    print(fm.group(1))
    sys.exit(0)

# Strategy 2: First yaml code fence
fence = re.search(r'\`\`\`ya?ml\s*\n(.*?)\n\`\`\`', content, re.DOTALL)
if fence:
    print(fence.group(1))
    sys.exit(0)

# Strategy 3: All yaml code fences combined
fences = re.findall(r'\`\`\`ya?ml\s*\n(.*?)\n\`\`\`', content, re.DOTALL)
if fences:
    print('\n'.join(fences))
    sys.exit(0)

sys.exit(1)
" "$file" 2>/dev/null
}

# ── Compute per-section hashes and snapshots ───────────────────────────────
# Uses Python to parse YAML subset, split into top-level sections,
# hash each section, and produce a hashes JSON.

compute_section_hashes() {
  local yaml_text="$1"
  local _py_script
  _py_script=$(pipeline_mktemp)
  cat > "$_py_script" << 'PYEOF'
import sys, re, json, hashlib, datetime

def parse_yaml_subset(text):
    result = {}
    stack = [(result, -1)]
    for line in text.split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())

        list_match = re.match(r"^(\s*)- (.+)$", line)
        if list_match:
            continue

        kv_match = re.match(r"^(\s*)([a-zA-Z_][a-zA-Z0-9_.-]*)\s*:\s*(.*?)$", line)
        if not kv_match:
            continue
        key = kv_match.group(2)
        raw_val = kv_match.group(3).strip()

        while len(stack) > 1 and stack[-1][1] >= indent:
            stack.pop()
        parent = stack[-1][0]

        if raw_val and not raw_val.startswith(('"', "'", "[")):
            comment_pos = raw_val.find(" #")
            if comment_pos > 0:
                raw_val = raw_val[:comment_pos].strip()

        if raw_val == "" or raw_val is None:
            new_dict = {}
            parent[key] = new_dict
            stack.append((new_dict, indent))
        else:
            parent[key] = parse_value(raw_val)

    return result

def parse_value(s):
    if not s:
        return None
    s = s.strip()
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        return s[1:-1]
    if s.lower() in ("true", "yes", "on"):
        return True
    if s.lower() in ("false", "no", "off"):
        return False
    if s.lower() in ("null", "~"):
        return None
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s)
    except ValueError:
        pass
    if s.startswith("[") and s.endswith("]"):
        items = s[1:-1].split(",")
        return [parse_value(i.strip()) for i in items if i.strip()]
    return s

yaml_text = sys.stdin.read()
data = parse_yaml_subset(yaml_text)

file_hash = hashlib.sha256(yaml_text.encode()).hexdigest()

sections = {}
for key, val in data.items():
    section_str = json.dumps(val, sort_keys=True)
    section_hash = hashlib.sha256(section_str.encode()).hexdigest()
    sections[key] = {
        "hash": section_hash,
        "value_snapshot": val
    }

output = {
    "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "file_hash": file_hash,
    "sections": sections
}

print(json.dumps(output, indent=2))
PYEOF
  echo "$yaml_text" | "$FORGE_PYTHON" "$_py_script"
  local rc=$?
  rm -f "$_py_script"
  return $rc
}

# ── Detect retrospective attribution ──────────────────────────────────────

detect_attribution() {
  local config_content
  config_content=$(cat "$CONFIG_FILE")

  "$FORGE_PYTHON" -c '
import sys, re

content = sys.argv[1]
# Find retrospective tuning comments
# Format: <!-- tuned by retrospective: {run_id} -->
tuned = re.findall(r"<!--\s*tuned by retrospective[^>]*-->", content)
if tuned:
    print("retrospective")
else:
    print("unknown")
' "$config_content" 2>/dev/null
}

# ── Main logic ─────────────────────────────────────────────────────────────

YAML_TEXT=$(extract_yaml "$CONFIG_FILE") || {
  echo "ERROR: Could not extract YAML from forge-config.md" >&2
  exit 2
}

CURRENT_HASHES=$(compute_section_hashes "$YAML_TEXT") || {
  echo "ERROR: Could not compute section hashes" >&2
  exit 2
}

# Snapshot mode: save and exit
if $SNAPSHOT_ONLY; then
  echo "$CURRENT_HASHES" > "$HASHES_FILE"
  echo "Snapshot saved to $HASHES_FILE"
  exit 0
fi

# If no previous hashes, this is the first run — save and report no diff
if [[ ! -f "$HASHES_FILE" ]]; then
  echo "$CURRENT_HASHES" > "$HASHES_FILE"
  if $JSON_OUTPUT; then
    echo '{"changes": [], "unchanged_sections": [], "first_run": true}'
  else
    echo "[INFO] [config-diff] First run — no previous config hashes to compare against."
    echo "[INFO] [config-diff] Snapshot saved."
  fi
  exit 0
fi

# ── Diff previous vs current ──────────────────────────────────────────────

PREVIOUS_HASHES=$(cat "$HASHES_FILE")
ATTRIBUTION=$(detect_attribution)

DIFF_RESULT=$("$FORGE_PYTHON" -c '
import json, sys

previous = json.loads(sys.argv[1])
current = json.loads(sys.argv[2])
attribution_hint = sys.argv[3]

prev_sections = previous.get("sections", {})
curr_sections = current.get("sections", {})

changes = []
unchanged = []

# Check all sections in current
all_keys = set(list(prev_sections.keys()) + list(curr_sections.keys()))
for key in sorted(all_keys):
    prev_entry = prev_sections.get(key)
    curr_entry = curr_sections.get(key)

    if prev_entry is None and curr_entry is not None:
        # New section
        changes.append({
            "section": key,
            "type": "added",
            "previous": None,
            "current": curr_entry.get("value_snapshot"),
            "changed_by": attribution_hint if attribution_hint != "unknown" else "user"
        })
    elif curr_entry is None and prev_entry is not None:
        # Removed section
        changes.append({
            "section": key,
            "type": "removed",
            "previous": prev_entry.get("value_snapshot"),
            "current": None,
            "changed_by": "user"
        })
    elif prev_entry["hash"] != curr_entry["hash"]:
        # Changed section — compute field-level diff
        prev_val = prev_entry.get("value_snapshot", {})
        curr_val = curr_entry.get("value_snapshot", {})

        if isinstance(prev_val, dict) and isinstance(curr_val, dict):
            for field in set(list(prev_val.keys()) + list(curr_val.keys())):
                pv = prev_val.get(field)
                cv = curr_val.get(field)
                if pv != cv:
                    changes.append({
                        "section": key,
                        "field": field,
                        "type": "modified",
                        "previous": pv,
                        "current": cv,
                        "changed_by": attribution_hint if attribution_hint != "unknown" else "user"
                    })
        else:
            changes.append({
                "section": key,
                "type": "modified",
                "previous": prev_val,
                "current": curr_val,
                "changed_by": attribution_hint if attribution_hint != "unknown" else "user"
            })
    else:
        unchanged.append(key)

# Detect forge-init (all sections changed simultaneously)
if len(changes) > 0 and len(unchanged) == 0 and len(prev_sections) > 0:
    for c in changes:
        c["changed_by"] = "forge-init (full regeneration)"

result = {
    "changes": changes,
    "unchanged_sections": unchanged
}

print(json.dumps(result, indent=2))
' "$PREVIOUS_HASHES" "$CURRENT_HASHES" "$ATTRIBUTION") || {
  echo "ERROR: Could not compute diff" >&2
  exit 2
}

# Save current snapshot for next run
echo "$CURRENT_HASHES" > "$HASHES_FILE"

# ── Output ──────────────────────────────────────────────────────────────────

HAS_CHANGES=$("$FORGE_PYTHON" -c "
import json, sys
data = json.loads(sys.argv[1])
print('true' if data.get('changes') else 'false')
" "$DIFF_RESULT")

if $JSON_OUTPUT; then
  echo "$DIFF_RESULT"
else
  if [[ "$HAS_CHANGES" == "true" ]]; then
    echo "[INFO] [config-diff] forge-config.md changes since last run:"
    "$FORGE_PYTHON" -c "
import json, sys
data = json.loads(sys.argv[1])
for c in data['changes']:
    section = c['section']
    field = c.get('field', '')
    path = f'{section}.{field}' if field else section
    change_type = c['type']
    changed_by = c.get('changed_by', 'unknown')
    if change_type == 'added':
        print(f'  + {path}: {c[\"current\"]} (added by: {changed_by})')
    elif change_type == 'removed':
        print(f'  - {path}: (removed)')
    else:
        print(f'  ~ {path}: {c.get(\"previous\", \"?\")} -> {c.get(\"current\", \"?\")} (changed by: {changed_by})')

unchanged = data.get('unchanged_sections', [])
if unchanged:
    print(f'  Unchanged: {\", \".join(unchanged)}')
" "$DIFF_RESULT"
  else
    echo "[INFO] [config-diff] No changes to forge-config.md since last run."
  fi
fi

if [[ "$HAS_CHANGES" == "true" ]]; then
  exit 1
else
  exit 0
fi
