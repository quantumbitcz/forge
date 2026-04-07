#!/usr/bin/env bash
set -euo pipefail

# Layer-2 linter adapter: scalafmt (Scala formatter/linter)
# Input:  $1=project_root  $2=target_path  $3=severity-map.json
# Output: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0=ok  1=not installed  2=linter error

PROJECT_ROOT="${1:?usage: scalafmt.sh PROJECT_ROOT TARGET SEVERITY_MAP}"
TARGET="${2:?}"
SEVERITY_MAP="${3:?}"

# --- availability check ---
if ! command -v scalafmt &>/dev/null; then
  exit 1
fi

# --- run linter (check mode — report unformatted files) ---
RAW=$(mktemp "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/linter.XXXXXX")
trap 'rm -f "$RAW"' EXIT

RC=0
scalafmt --check --non-interactive "$TARGET" 2>"$RAW" 1>/dev/null || RC=$?

# scalafmt --check exits 1 if files need formatting, prints to stderr
if [[ $RC -eq 0 ]]; then
  # all files formatted — no findings
  exit 0
fi

# --- parse findings ---
# scalafmt --check outputs lines like:
#   error: /path/to/File.scala is not formatted
_PY="python3"; command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then exit 0; fi
"$_PY" -c "
import sys, re

raw_path = sys.argv[1]

with open(raw_path) as f:
    for line in f:
        line = line.strip()
        m = re.match(r'(?:error:\s*)?(.+?)\s+is not formatted', line)
        if m:
            filepath = m.group(1)
            print(f'{filepath}:1 | SCALA-LINT-FMT | INFO | File not formatted per scalafmt rules | Run: scalafmt {filepath}')
" "$RAW"

exit 0
