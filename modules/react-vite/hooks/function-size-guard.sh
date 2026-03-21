#!/bin/bash
# PostToolUse hook: Warns on functions > 30 lines or nesting depth > 3.
# Scope: .ts/.tsx files

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

awk '
BEGIN {
  depth = 0
  func_name = ""
  func_start = 0
  func_depth = 0
  in_func = 0
  max_nesting = 0
  line_count = 0
}

# Detect function declarations
/^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(function|const|let)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/ {
  if (in_func == 0 || depth <= func_depth) {
    # Extract function name
    name = $0
    gsub(/^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(function|const|let)[[:space:]]+/, "", name)
    gsub(/[^A-Za-z0-9_].*/, "", name)
    if (name != "" && index($0, "{") > 0) {
      func_name = name
      func_start = NR
      func_depth = depth
      in_func = 1
      line_count = 0
      max_nesting = 0
    }
  }
}

{
  # Count braces
  line = $0
  # Remove strings and comments (simplified)
  gsub(/"[^"]*"/, "", line)
  gsub(/'\''[^'\'']*'\''/, "", line)
  gsub(/`[^`]*`/, "", line)
  gsub(/\/\/.*$/, "", line)

  opens = gsub(/{/, "{", line)
  closes = gsub(/}/, "}", line)

  depth += opens
  if (in_func) {
    line_count++
    current_nesting = depth - func_depth
    if (current_nesting > max_nesting) {
      max_nesting = current_nesting
    }
  }
  depth -= closes

  # Check if function ended
  if (in_func && depth <= func_depth) {
    if (line_count > 30) {
      printf "⚠ function-size-guard: line %d: function \"%s\" is %d lines (max ~30)\n", func_start, func_name, line_count
    }
    if (max_nesting > 3) {
      printf "⚠ function-size-guard: line %d: function \"%s\" has nesting depth %d (max 3)\n", func_start, func_name, max_nesting
    }
    in_func = 0
    func_name = ""
  }
}
' "$abs" 2>/dev/null || true

exit 0
