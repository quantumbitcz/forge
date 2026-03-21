#!/usr/bin/env bash
# PostToolUse hook: Warns when wellplanned-core imports from adapter packages.
# This is the most critical hexagonal architecture violation — core must never
# depend on adapters. Catches at write-time before the build fails.
# Exit 0 always (warnings only, never blocks).

set -euo pipefail

# Extract file path from TOOL_INPUT JSON
FILE=$(echo "$TOOL_INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*\.kt"' | grep -oE '/[^"]*\.kt' | head -1)
if [ -z "$FILE" ]; then
  FILE=$(echo "$TOOL_INPUT" | grep -oE '[^ "]*\.kt' | head -1)
fi

# Only check files in wellplanned-core/src/main
if [ -z "$FILE" ]; then exit 0; fi
if ! echo "$FILE" | grep -qE 'wellplanned-core/src/main'; then exit 0; fi
if [ ! -f "$FILE" ]; then exit 0; fi

# Check for adapter package imports
LINES=$(grep -nE 'import\s+cz\.quantumbit\.wellplanned\.adapter\.' "$FILE" 2>/dev/null || true)
if [ -n "$LINES" ]; then
  SAMPLE=$(echo "$LINES" | head -3)
  echo "WARNING [CRITICAL]: Core module importing from adapter — hexagonal architecture violation!"
  echo "Core must never depend on adapters. Use port interfaces instead."
  echo "$SAMPLE"
  exit 0
fi

# Check for Spring Data / R2DBC imports (framework types in domain)
if echo "$FILE" | grep -qE 'core/domain/'; then
  LINES=$(grep -nE 'import\s+org\.springframework\.(data|r2dbc)\.' "$FILE" 2>/dev/null || true)
  if [ -n "$LINES" ]; then
    SAMPLE=$(echo "$LINES" | head -3)
    echo "WARNING [HIGH]: Domain model importing Spring Data/R2DBC types — keep domain framework-free."
    echo "$SAMPLE"
  fi
fi
