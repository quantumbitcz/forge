#!/usr/bin/env bash
# Lightweight antipattern checker for Kotlin files.
# Called by PostToolUse hook on Edit/Write of .kt files.
# Reads the file path from TOOL_INPUT, checks for common issues, and warns.
# Exit 0 always (warnings only, never blocks).
# Uses only POSIX/macOS-compatible grep (no -P flag).

set -euo pipefail

# Extract file path from TOOL_INPUT JSON (try JSON field first, then fallback to bare path)
FILE=$(echo "$TOOL_INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*\.kt"' | grep -oE '/[^"]*\.kt' | head -1)
if [ -z "$FILE" ]; then
  FILE=$(echo "$TOOL_INPUT" | grep -oE '[^ "]*\.kt' | head -1)
fi

# Skip non-Kotlin, generated sources
if [ -z "$FILE" ]; then exit 0; fi
if echo "$FILE" | grep -qE 'build/generated-sources'; then exit 0; fi
if [ ! -f "$FILE" ]; then exit 0; fi

WARNINGS=""

# 1. Non-null assertion (!!) — skip comments, strings, and KDoc
# Match !! that is NOT inside a string literal or comment
LINES=$(grep -n '!!' "$FILE" | grep -vE '^\s*[0-9]+:\s*//' | grep -vE '^\s*[0-9]+:\s*\*' | grep -vE '"[^"]*!![^"]*"' | grep -vE '//.*!!' || true)
if [ -n "$LINES" ]; then
  SAMPLE=$(echo "$LINES" | head -3)
  WARNINGS="${WARNINGS}WARNING [HIGH]: Non-null assertion (!!) — use safe calls or Elvis operator:
${SAMPLE}

"
fi

# 2. Blocking calls in coroutine context
LINES=$(grep -nE 'Thread\.sleep|runBlocking' "$FILE" | grep -vE '^\s*[0-9]+:\s*//' || true)
if [ -n "$LINES" ]; then
  SAMPLE=$(echo "$LINES" | head -3)
  WARNINGS="${WARNINGS}WARNING [HIGH]: Blocking call in reactive/coroutine codebase — use delay() or withContext(Dispatchers.IO):
${SAMPLE}

"
fi

# 2b. Thread/Executor usage instead of coroutines
LINES=$(grep -nE 'Thread\(|Executors\.|newFixedThreadPool|newCachedThreadPool|newSingleThreadExecutor|synchronized[[:space:]]*\(' "$FILE" | grep -vE '^\s*[0-9]+:\s*//' || true)
if [ -n "$LINES" ]; then
  SAMPLE=$(echo "$LINES" | head -3)
  WARNINGS="${WARNINGS}WARNING [HIGH]: Thread/Executor usage — use coroutines instead (launch, async, withContext):
${SAMPLE}

"
fi

# 3. Hardcoded credentials (not in test files)
if ! echo "$FILE" | grep -qE '/test/'; then
  LINES=$(grep -niE '(password|secret|token|apikey)[[:space:]]*=[[:space:]]*"[^"]{3,}"' "$FILE" | grep -vE '^\s*[0-9]+:\s*//' || true)
  if [ -n "$LINES" ]; then
    SAMPLE=$(echo "$LINES" | head -3)
    WARNINGS="${WARNINGS}WARNING [CRITICAL]: Possible hardcoded credential:
${SAMPLE}

"
  fi
fi

# 4. println / System.out in non-test code
if ! echo "$FILE" | grep -qE '/test/'; then
  LINES=$(grep -nE 'println\(|System\.(out|err)\.' "$FILE" | grep -vE '^\s*[0-9]+:\s*//' || true)
  if [ -n "$LINES" ]; then
    SAMPLE=$(echo "$LINES" | head -3)
    WARNINGS="${WARNINGS}WARNING [LOW]: Console output — use logger instead:
${SAMPLE}

"
  fi
fi

# 5. @Transactional on adapter classes
if echo "$FILE" | grep -qE '/adapter/'; then
  if grep -qE '@Transactional' "$FILE"; then
    WARNINGS="${WARNINGS}WARNING [HIGH]: @Transactional on adapter class — should be on use case only

"
  fi
fi

# 6. java.util.UUID or java.time in core domain
if echo "$FILE" | grep -qE 'wellplanned-core/src/main'; then
  if grep -qE 'import java\.util\.UUID' "$FILE"; then
    WARNINGS="${WARNINGS}WARNING [HIGH]: java.util.UUID in core — use kotlin.uuid.Uuid with typed ID wrapper

"
  fi
  if grep -qE 'import java\.time\.' "$FILE"; then
    WARNINGS="${WARNINGS}WARNING [HIGH]: java.time in core — use kotlinx.datetime.Instant

"
  fi
fi

# 7. Raw Exception throw (not domain-specific)
LINES=$(grep -nE 'throw (Exception|RuntimeException)\(' "$FILE" | grep -vE '^\s*[0-9]+:\s*//' || true)
if [ -n "$LINES" ]; then
  SAMPLE=$(echo "$LINES" | head -3)
  WARNINGS="${WARNINGS}WARNING [MEDIUM]: Generic exception — use domain-specific exceptions:
${SAMPLE}

"
fi

if [ -n "$WARNINGS" ]; then
  echo "--- Antipattern scan for $(basename "$FILE") ---"
  echo "$WARNINGS"
  echo "Run /scan fix to auto-fix these issues."
fi
