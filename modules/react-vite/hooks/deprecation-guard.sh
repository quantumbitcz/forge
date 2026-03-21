#!/bin/bash
# PostToolUse hook: Warns when known deprecated patterns are found.
# Scope: all .ts/.tsx files

filepath=$(echo "$CLAUDE_TOOL_INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

case "$filepath" in
  *.ts|*.tsx) ;;
  *) exit 0 ;;
esac

# Resolve to absolute path if needed
if [[ "$filepath" = /* ]]; then
  abs="$filepath"
else
  abs="$(pwd)/$filepath"
fi

[ ! -f "$abs" ] && exit 0

# Read deprecations from known-deprecations.json
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPRECATIONS_FILE="$SCRIPT_DIR/../known-deprecations.json"

[ ! -f "$DEPRECATIONS_FILE" ] && exit 0

# Parse deprecation entries — try python3 first, fall back to sed
extract_deprecations() {
  if command -v python3 &>/dev/null; then
    python3 -c "
import json, sys
with open('$DEPRECATIONS_FILE') as f:
    data = json.load(f)
for d in data.get('deprecations', []):
    print(d['pattern'] + '|||' + d['replacement'])
" 2>/dev/null
  else
    # sed fallback: extract pattern/replacement pairs from JSON
    sed -n '/"pattern"/{ s/.*"pattern"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/; h; n; s/.*"replacement"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/; H; g; s/\n/|||/; p; }' "$DEPRECATIONS_FILE" 2>/dev/null
  fi
}

entries=$(extract_deprecations)
[ -z "$entries" ] && exit 0

echo "$entries" | while IFS= read -r entry; do
  pattern=$(echo "$entry" | sed 's/|||.*//')
  replacement=$(echo "$entry" | sed 's/.*|||//')

  matches=$(grep -En "$pattern" "$abs" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    echo "$matches" | while IFS= read -r line; do
      lineno=$(echo "$line" | cut -d: -f1)
      echo "⚠ deprecation-guard: line $lineno: '$pattern' found — $replacement"
    done
  fi
done

exit 0
