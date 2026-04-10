#!/usr/bin/env bash
# Validates a single finding line against the output-format.md spec.
# Usage: echo "finding line" | validate-finding.sh
#        validate-finding.sh "finding line"
# Exit 0 = valid, Exit 1 = invalid (reason on stderr)
set -uo pipefail

# Accept input from argument or stdin
if [[ $# -ge 1 ]]; then
  LINE="$1"
else
  IFS= read -r LINE
fi

if [[ -z "${LINE:-}" ]]; then
  echo "ERROR: empty finding line" >&2
  exit 1
fi

# Split on ' | ' delimiter
# Append sentinel to preserve trailing empty fields (bash read strips them)
NORMALIZED="$(echo "$LINE" | sed 's/ | /|/g')"
IFS='|' read -ra RAW_FIELDS <<< "${NORMALIZED}|__SENTINEL__"

# Remove the sentinel entry
unset 'RAW_FIELDS[${#RAW_FIELDS[@]}-1]'

FIELD_COUNT=${#RAW_FIELDS[@]}

# Trim whitespace from each field
FIELDS=()
for f in "${RAW_FIELDS[@]}"; do
  trimmed="$(echo "$f" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  FIELDS+=("$trimmed")
done

FIELD_COUNT=${#FIELDS[@]}

# Must have exactly 5 or 6 fields
if [[ $FIELD_COUNT -lt 5 ]]; then
  echo "ERROR: expected 5 or 6 fields, got $FIELD_COUNT" >&2
  exit 1
fi

if [[ $FIELD_COUNT -gt 6 ]]; then
  echo "ERROR: expected 5 or 6 fields, got $FIELD_COUNT" >&2
  exit 1
fi

# Field 1: file:line — must contain ':' with numeric line (or '?:0')
FILE_LINE="${FIELDS[0]}"
if ! echo "$FILE_LINE" | grep -qE '^[^:]+:[0-9]+$'; then
  echo "ERROR: field 1 (file:line) must match 'file:number', got: $FILE_LINE" >&2
  exit 1
fi

# Field 2: CATEGORY-CODE — must match ^[A-Z][A-Z0-9-]+$
CATEGORY="${FIELDS[1]}"
if ! echo "$CATEGORY" | grep -qE '^[A-Z][A-Z0-9]+-[A-Z0-9_-]+$'; then
  echo "ERROR: field 2 (CATEGORY-CODE) must match 'PREFIX-CODE' uppercase pattern, got: $CATEGORY" >&2
  exit 1
fi

# Field 3: SEVERITY — must be exactly CRITICAL, WARNING, or INFO
SEVERITY="${FIELDS[2]}"
if [[ "$SEVERITY" != "CRITICAL" && "$SEVERITY" != "WARNING" && "$SEVERITY" != "INFO" ]]; then
  echo "ERROR: field 3 (SEVERITY) must be CRITICAL, WARNING, or INFO, got: $SEVERITY" >&2
  exit 1
fi

# Field 4: message — must be non-empty
MESSAGE="${FIELDS[3]}"
if [[ -z "$MESSAGE" ]]; then
  echo "ERROR: field 4 (message) must be non-empty" >&2
  exit 1
fi

# Field 5: fix_hint — may be empty string (valid)
# No validation needed

# Field 6 (optional): confidence — must match confidence:(HIGH|MEDIUM|LOW) if present
if [[ $FIELD_COUNT -eq 6 ]]; then
  CONFIDENCE="${FIELDS[5]}"
  if ! echo "$CONFIDENCE" | grep -qE '^confidence:(HIGH|MEDIUM|LOW)$'; then
    echo "ERROR: field 6 (confidence) must match 'confidence:(HIGH|MEDIUM|LOW)', got: $CONFIDENCE" >&2
    exit 1
  fi
fi

exit 0
