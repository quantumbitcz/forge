#!/bin/bash
# PostToolUse hook: Warns when a file exceeds ~400 lines.

filepath=$(echo "$CLAUDE_TOOL_INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

[ -z "$filepath" ] && exit 0

# Resolve to absolute path if needed
if [[ "$filepath" = /* ]]; then
  abs="$filepath"
else
  abs="$(pwd)/$filepath"
fi

[ ! -f "$abs" ] && exit 0

count=$(wc -l < "$abs" 2>/dev/null || echo "0")
count=$(echo "$count" | tr -d ' ')

if [ "$count" -gt 400 ]; then
  echo "⚠ file-size-guard: $filepath has $count lines (max ~400). Consider extracting sub-components."
fi

exit 0
