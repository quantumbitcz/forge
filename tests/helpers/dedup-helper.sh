#!/usr/bin/env bash
# Implements the dedup algorithm from scoring.md for testing.
# Input: pipe-delimited finding lines on stdin (one per line)
# Optional first argument: "multi" to use component-aware dedup
# Output: deduplicated finding lines on stdout
#
# Finding format: file:line | CATEGORY-CODE | SEVERITY | message | fix_hint
# Multi-component: component | file:line | CATEGORY-CODE | SEVERITY | message | fix_hint
set -uo pipefail

MODE="${1:-single}"

# Read all findings into an array
mapfile -t LINES < /dev/stdin

# Use python3 for reliable dedup (handles edge cases better than pure bash)
python3 -c "
import sys

mode = sys.argv[1]
lines = sys.argv[2:]

severity_order = {'CRITICAL': 3, 'WARNING': 2, 'INFO': 1}

groups = {}  # key -> (severity_rank, finding_line, description_len, fix_hint)

for line in lines:
    if not line.strip():
        continue

    parts = [p.strip() for p in line.split(' | ')]

    if mode == 'multi' and len(parts) >= 6:
        component = parts[0]
        file_line = parts[1]
        category = parts[2]
        severity = parts[3]
        message = parts[4]
        fix_hint = parts[5] if len(parts) > 5 else ''
        key = (component, file_line, category)
        original_line = line
    elif len(parts) >= 5:
        file_line = parts[0]
        category = parts[1]
        severity = parts[2]
        message = parts[3]
        fix_hint = parts[4] if len(parts) > 4 else ''
        key = (file_line, category)
        original_line = line
    else:
        # Malformed, pass through
        print(line)
        continue

    # Skip SCOUT-* from dedup (pass through as-is)
    if category.startswith('SCOUT-'):
        print(line)
        continue

    sev_rank = severity_order.get(severity, 0)

    if key not in groups:
        groups[key] = (sev_rank, severity, message, fix_hint, line)
    else:
        existing = groups[key]
        # Keep highest severity
        if sev_rank > existing[0]:
            groups[key] = (sev_rank, severity, message, fix_hint, line)
        elif sev_rank == existing[0]:
            # Tie: keep longest description
            if len(message) > len(existing[2]):
                groups[key] = (sev_rank, severity, message, fix_hint, line)

# Output deduplicated findings
for key in groups:
    print(groups[key][4])
" "$MODE" "${LINES[@]}"
