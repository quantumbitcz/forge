#!/usr/bin/env bats
# Structural test: enforce 15-line soft cap on module overview sections

load '../helpers/test-helpers'

@test "module overview sections do not exceed 15 lines" {
  local violations=0
  for conv in "$PLUGIN_ROOT"/modules/frameworks/*/conventions.md; do
    # Extract the Overview section (between ## Overview and next ##)
    local overview_lines
    overview_lines=$(sed -n '/^## Overview/,/^## /p' "$conv" | head -n -1 | wc -l | tr -d ' ')
    # Handle files without ## Overview gracefully (0 lines = no section = OK)
    if [[ "$overview_lines" -gt 15 ]]; then
      echo "VIOLATION: $conv Overview section is $overview_lines lines (max 15)"
      violations=$((violations + 1))
    fi
  done
  [[ "$violations" -eq 0 ]]
}
