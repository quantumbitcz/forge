#!/usr/bin/env bash
# PostToolUse hook: Warns when a Kotlin file exceeds size thresholds.
# Hexagonal architecture keeps files focused — large files signal a design smell.
# Exit 0 always (warnings only, never blocks).

set -euo pipefail

# Extract file path from TOOL_INPUT JSON
FILE=$(echo "$TOOL_INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*\.kt"' | grep -oE '/[^"]*\.kt' | head -1)
if [ -z "$FILE" ]; then
  FILE=$(echo "$TOOL_INPUT" | grep -oE '[^ "]*\.kt' | head -1)
fi

# Skip non-Kotlin, generated sources, test files
if [ -z "$FILE" ]; then exit 0; fi
if echo "$FILE" | grep -qE 'build/generated-sources'; then exit 0; fi
if [ ! -f "$FILE" ]; then exit 0; fi

COUNT=$(wc -l < "$FILE" 2>/dev/null || echo "0")
COUNT=$(echo "$COUNT" | tr -d ' ')

# Determine threshold based on file type/location
THRESHOLD=300
LABEL="file"

if echo "$FILE" | grep -qE 'core/impl/'; then
  THRESHOLD=150
  LABEL="use case implementation"
elif echo "$FILE" | grep -qE 'core/input/usecase/|core/output/port/'; then
  THRESHOLD=100
  LABEL="port/use case interface"
elif echo "$FILE" | grep -qE 'adapter/.*/adapter/'; then
  THRESHOLD=200
  LABEL="persistence adapter"
elif echo "$FILE" | grep -qE 'controller/'; then
  THRESHOLD=250
  LABEL="controller"
elif echo "$FILE" | grep -qE 'mapper/'; then
  THRESHOLD=200
  LABEL="mapper"
fi

if [ "$COUNT" -gt "$THRESHOLD" ]; then
  echo "WARNING [MEDIUM]: $(basename "$FILE") is $COUNT lines ($LABEL max ~$THRESHOLD). Consider extracting helper functions or splitting responsibilities."
fi
