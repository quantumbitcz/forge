#!/bin/bash
# PostToolUse hook: Warns on hardcoded colors and Tailwind font-size classes in component files.
# Scope: .tsx files under src/app/components/ (excluding ui/)

filepath=$(echo "$CLAUDE_TOOL_INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Guard: must be a .tsx file under src/app/components/ but not ui/
case "$filepath" in
  */src/app/components/ui/*|src/app/components/ui/*) exit 0 ;;
  */src/app/components/*|src/app/components/*) ;;
  *) exit 0 ;;
esac

[[ "$filepath" != *.tsx ]] && exit 0

# Resolve to absolute path if needed
if [[ "$filepath" = /* ]]; then
  abs="$filepath"
else
  abs="$(pwd)/$filepath"
fi

[ ! -f "$abs" ] && exit 0

# Check for hardcoded color classes
hardcoded=$(grep -n -E '\b(bg-white|bg-black|bg-gray-|bg-slate-|bg-zinc-|text-white|text-black|text-gray-|text-slate-)\b' "$abs" 2>/dev/null || true)
if [ -n "$hardcoded" ]; then
  echo "$hardcoded" | while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    match=$(echo "$line" | grep -oE '\b(bg-white|bg-black|bg-gray-[0-9]+|bg-slate-[0-9]+|bg-zinc-[0-9]+|text-white|text-black|text-gray-[0-9]+|text-slate-[0-9]+)\b' | head -1)
    case "$match" in
      bg-white)       suggest="bg-background or bg-card" ;;
      bg-black)       suggest="bg-foreground" ;;
      bg-gray-*|bg-slate-*|bg-zinc-*) suggest="bg-muted or bg-accent" ;;
      text-white)     suggest="text-background or text-primary-foreground" ;;
      text-black)     suggest="text-foreground" ;;
      text-gray-*|text-slate-*) suggest="text-muted-foreground" ;;
      *)              suggest="a theme token" ;;
    esac
    echo "⚠ theme-guard: line $lineno: $match → use $suggest"
  done
fi

# Check for Tailwind font-size classes
fontsizes=$(grep -n -E '\btext-(xs|sm|base|lg|xl|2xl|3xl)\b' "$abs" 2>/dev/null || true)
if [ -n "$fontsizes" ]; then
  echo "$fontsizes" | while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    match=$(echo "$line" | grep -oE '\btext-(xs|sm|base|lg|xl|2xl|3xl)\b' | head -1)
    echo "⚠ theme-guard: line $lineno: $match → use style={{ fontSize }} with the project type scale"
  done
fi

exit 0
