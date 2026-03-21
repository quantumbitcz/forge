#!/bin/bash
# PostToolUse hook: Warns when import order violates the project convention.
# Expected: React → third-party → @/app/components/shared → feature-local (./ ../)
# Scope: .ts/.tsx files under src/app/components/ (excluding ui/)

filepath=$(echo "$CLAUDE_TOOL_INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Guard: must be a .ts/.tsx file under src/app/components/ but not ui/
case "$filepath" in
  src/app/components/ui/*|*/src/app/components/ui/*) exit 0 ;;
  src/app/components/*|*/src/app/components/*) ;;
  *) exit 0 ;;
esac

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

# Classify imports: 1=react, 2=third-party, 3=internal-shared, 4=feature-local
last_group=0
warned=0

while IFS= read -r line; do
  lineno=$(echo "$line" | cut -d: -f1)
  content=$(echo "$line" | cut -d: -f2-)

  # Determine group by extracting the module specifier
  group=0
  # Extract the module path from the import statement
  modpath=$(echo "$content" | sed -n "s/.*from[[:space:]]*['\"][[:space:]]*\([^'\"]*\).*/\1/p")

  if [ -z "$modpath" ]; then
    continue
  fi

  case "$modpath" in
    react|react/*) group=1 ;;
    ./*|../*) group=4 ;;
    @/app/components/shared|@/app/components/shared/*) group=3 ;;
    @/*) group=2 ;;
    *) group=2 ;;
  esac

  [ "$group" -eq 0 ] && continue

  if [ "$group" -lt "$last_group" ]; then
    echo "⚠ import-order-guard: line $lineno: import appears out of order (group $group after group $last_group)"
    echo "  Expected: React → third-party → internal (@/) → feature-local (./)"
    echo "  Line: $(echo "$content" | sed 's/^[[:space:]]*//')"
    warned=1
  fi

  last_group=$group
done < <(grep -n "^import " "$abs" 2>/dev/null || true)

exit 0
