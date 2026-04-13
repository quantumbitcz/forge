#!/usr/bin/env bash
# Dispatches forge skills based on automation trigger events.
# Reads automation rules from forge-config.md, enforces cooldowns,
# and logs all dispatch decisions to .forge/automation-log.jsonl.
#
# Usage:
#   automation-trigger.sh --trigger <type> --payload '<json>'
#     [--forge-dir .forge] [--config path/to/forge-config.md]
#
# Exit codes: 0 = dispatched or skipped (cooldown), 1 = error, 2 = no matching automation.

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────

FORGE_DIR=".forge"
CONFIG=""
TRIGGER=""
PAYLOAD="{}"

# ── Arg Parsing ─────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge-dir)  FORGE_DIR="$2"; shift 2 ;;
    --config)     CONFIG="$2"; shift 2 ;;
    --trigger)    TRIGGER="$2"; shift 2 ;;
    --payload)    PAYLOAD="$2"; shift 2 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TRIGGER" ]]; then
  echo "ERROR: --trigger is required" >&2
  exit 1
fi

# ── Resolve Config ──────────────────────────────────────────────────────────

if [[ -z "$CONFIG" ]]; then
  # Search standard locations
  for candidate in ".claude/forge-config.md" "$FORGE_DIR/forge-config.md"; do
    if [[ -f "$candidate" ]]; then
      CONFIG="$candidate"
      break
    fi
  done
fi

if [[ -z "$CONFIG" || ! -f "$CONFIG" ]]; then
  echo "ERROR: config not found (tried .claude/forge-config.md, $FORGE_DIR/forge-config.md)" >&2
  exit 1
fi

# ── Python Detection ────────────────────────────────────────────────────────

_py=""
command -v python3 &>/dev/null && _py="python3"
[[ -z "$_py" ]] && command -v python &>/dev/null && _py="python"

if [[ -z "$_py" ]]; then
  echo "ERROR: python3 or python required" >&2
  exit 1
fi

# ── Ensure Forge Dir ────────────────────────────────────────────────────────

mkdir -p "$FORGE_DIR" 2>/dev/null || true
LOG_FILE="$FORGE_DIR/automation-log.jsonl"

# ── Log Helper ──────────────────────────────────────────────────────────────

_log_entry() {
  local name="$1" trigger="$2" action="$3" result="$4"
  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  "$_py" -c "
import json, sys
entry = {
    'timestamp': sys.argv[1],
    'automation': sys.argv[2],
    'trigger': sys.argv[3],
    'action': sys.argv[4],
    'result': sys.argv[5]
}
print(json.dumps(entry))
" "$ts" "$name" "$trigger" "$action" "$result" >> "$LOG_FILE"
}

# ── Parse Automations from Config ───────────────────────────────────────────
#
# Expects a YAML block in forge-config.md like:
#
#   automations:
#     - name: auto-review-on-push
#       trigger: push
#       filter: "branch:main"
#       cooldown_minutes: 10
#       action: /forge-review
#     - name: nightly-health
#       trigger: schedule
#       cooldown_minutes: 1440
#       action: /codebase-health
#
# Parses the automations section and returns JSON array.

AUTOMATIONS=$("$_py" -c "
import sys, json, re

config_path = sys.argv[1]

with open(config_path) as f:
    content = f.read()

# Find the automations: block (YAML-like parsing)
automations = []
in_block = False
current = None

for line in content.splitlines():
    stripped = line.rstrip()

    # Start of automations section
    if re.match(r'^automations:\s*$', stripped):
        in_block = True
        continue

    # End of section: non-indented line after we started
    if in_block and stripped and not stripped.startswith(' ') and not stripped.startswith('-'):
        break

    if not in_block:
        continue

    # New list item
    if re.match(r'^\s*-\s+', stripped):
        if current:
            automations.append(current)
        current = {}
        # Handle key on same line as dash: '- name: foo'
        rest = re.sub(r'^\s*-\s+', '', stripped)
        if ':' in rest:
            k, v = rest.split(':', 1)
            current[k.strip()] = v.strip().strip('\"').strip(\"'\")
        continue

    # Continuation key within current item
    if current is not None and ':' in stripped:
        k, v = stripped.split(':', 1)
        k = k.strip()
        v = v.strip().strip('\"').strip(\"'\")
        if k == 'cooldown_minutes':
            try:
                v = int(v)
            except ValueError:
                v = 0
        current[k] = v

if current:
    automations.append(current)

print(json.dumps(automations))
" "$CONFIG" 2>/dev/null) || {
  echo "ERROR: failed to parse automations from $CONFIG" >&2
  exit 1
}

# ── Check for Empty Automations ─────────────────────────────────────────────

MATCH_COUNT=$("$_py" -c "
import json, sys
automations = json.loads(sys.argv[1])
trigger = sys.argv[2]
matches = [a for a in automations if a.get('trigger') == trigger]
print(len(matches))
" "$AUTOMATIONS" "$TRIGGER")

if [[ "$MATCH_COUNT" -eq 0 ]]; then
  exit 2
fi

# ── Process Matching Automations ────────────────────────────────────────────

"$_py" -c "
import json, sys, os, subprocess
from datetime import datetime, timedelta

automations = json.loads(sys.argv[1])
trigger = sys.argv[2]
payload = json.loads(sys.argv[3])
log_file = sys.argv[4]
forge_dir = sys.argv[5]

# Read existing log for cooldown checks
log_entries = []
if os.path.isfile(log_file):
    with open(log_file) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    log_entries.append(json.loads(line))
                except (json.JSONDecodeError, ValueError):
                    pass

now = datetime.utcnow()

def last_dispatch_time(name):
    \"\"\"Find the most recent successful dispatch for this automation.\"\"\"
    for entry in reversed(log_entries):
        if entry.get('automation') == name and entry.get('result') == 'dispatched':
            try:
                return datetime.strptime(entry['timestamp'], '%Y-%m-%dT%H:%M:%SZ')
            except (KeyError, ValueError):
                pass
    return None

def check_filter(filt, payload):
    \"\"\"Simple key:value filter matching against payload.\"\"\"
    if not filt:
        return True
    for part in filt.split(','):
        part = part.strip()
        if ':' not in part:
            continue
        k, v = part.split(':', 1)
        if payload.get(k.strip()) != v.strip():
            return False
    return True

results = []

for auto in automations:
    if auto.get('trigger') != trigger:
        continue

    name = auto.get('name', 'unnamed')
    action = auto.get('action', '')
    cooldown = int(auto.get('cooldown_minutes', 0))
    filt = auto.get('filter', '')

    # Check filter
    if not check_filter(filt, payload):
        results.append({'name': name, 'action': action, 'result': 'filtered'})
        continue

    # Check cooldown
    last = last_dispatch_time(name)
    if last and cooldown > 0:
        elapsed = (now - last).total_seconds() / 60.0
        if elapsed < cooldown:
            results.append({'name': name, 'action': action, 'result': 'cooldown',
                            'remaining_minutes': round(cooldown - elapsed, 1)})
            continue

    # Dispatch
    results.append({'name': name, 'action': action, 'result': 'dispatched'})

# Output results as JSON for the shell to process
print(json.dumps(results))
" "$AUTOMATIONS" "$TRIGGER" "$PAYLOAD" "$LOG_FILE" "$FORGE_DIR" | while IFS= read -r results_json; do

  # Process each result
  "$_py" -c "
import json, sys
results = json.loads(sys.argv[1])
for r in results:
    # Tab-separated: name, action, result, extra
    extra = ''
    if 'remaining_minutes' in r:
        extra = str(r['remaining_minutes'])
    print('{}\t{}\t{}\t{}'.format(r['name'], r['action'], r['result'], extra))
" "$results_json" | while IFS=$'\t' read -r name action result extra; do

    # Log every decision
    _log_entry "$name" "$TRIGGER" "$action" "$result"

    case "$result" in
      dispatched)
        echo "DISPATCH: $name → $action"
        # The action is a forge skill path like /forge-review
        # Caller is responsible for actual skill invocation; we print the action.
        ;;
      cooldown)
        echo "COOLDOWN: $name (${extra}min remaining)"
        ;;
      filtered)
        echo "FILTERED: $name (payload did not match filter)"
        ;;
    esac
  done
done

exit 0
