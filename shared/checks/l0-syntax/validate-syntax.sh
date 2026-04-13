#!/usr/bin/env bash
set -euo pipefail

# L0 Pre-Edit Syntax Validation
# PreToolUse hook for Edit|Write — validates that the resulting file parses cleanly.
# Exit 0 = allow edit. Exit 1 = block edit (stdout = error message to agent).
# Graceful degradation: if tree-sitter is not installed, exit 0 (allow).
#
# Environment variables (set by orchestrator at PREFLIGHT from config):
#   FORGE_L0_ENABLED    — "true" (default) or "false"
#   FORGE_L0_TIMEOUT_MS — max parse time in ms (default 500)
#   FORGE_L0_LANGUAGES  — "auto" (default) or space-separated language list

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-"$(cd "$SCRIPT_DIR/../../.." && pwd)"}"

# --- Logging helper ---
# Logs to .forge/.hook-failures.log for observability (best-effort, never fails).
_log_failure() {
  local reason="$1"
  local log_dir="${FORGE_DIR:-.forge}"
  if [[ -d "$log_dir" ]]; then
    local log_file="${log_dir}/.hook-failures.log"
    local entry
    entry="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u) | l0-syntax | ${reason} | ${FILE_PATH:-unknown}"
    echo "$entry" >> "$log_file" 2>/dev/null || true
  fi
}

# --- L0 stats counter ---
# Atomically increments a counter file in .forge/ (best-effort).
_increment_counter() {
  local counter_file="$1"
  local log_dir="${FORGE_DIR:-.forge}"
  [[ -d "$log_dir" ]] || return 0
  local path="${log_dir}/${counter_file}"
  local count=0
  [[ -f "$path" ]] && count=$(cat "$path" 2>/dev/null || echo 0)
  echo $((count + 1)) > "$path" 2>/dev/null || true
}

# --- Check L0 enabled ---
if [[ "${FORGE_L0_ENABLED:-true}" == "false" ]]; then
  exit 0
fi

# --- Check tree-sitter availability ---
if ! command -v tree-sitter &>/dev/null; then
  _log_failure "skip:tree-sitter_not_installed"
  exit 0
fi

# --- Check python availability ---
_PY="python3"
command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then
  _log_failure "skip:python_not_found"
  exit 0
fi

# --- Extract file path from TOOL_INPUT ---
FILE_PATH=""
TOOL_NAME="${TOOL_NAME:-}"
FILE_PATH=$("$_PY" -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d.get('file_path', ''))
" <<< "${TOOL_INPUT:-}" 2>/dev/null) || { _log_failure "skip:json_parse_failed"; exit 0; }

[[ -z "$FILE_PATH" ]] && exit 0

# --- Detect language from extension ---
LANG=""
EXT=".${FILE_PATH##*.}"
case "$EXT" in
  .kt|.kts)              LANG="kotlin" ;;
  .java)                 LANG="java" ;;
  .ts)                   LANG="typescript" ;;
  .tsx)                  LANG="tsx" ;;
  .js)                   LANG="javascript" ;;
  .jsx)                  LANG="jsx" ;;
  .py)                   LANG="python" ;;
  .go)                   LANG="go" ;;
  .rs)                   LANG="rust" ;;
  .cs|.csx)              LANG="c_sharp" ;;
  .c|.h)                 LANG="c" ;;
  .cpp|.cc|.cxx|.hpp)    LANG="cpp" ;;
  .swift)                LANG="swift" ;;
  .rb)                   LANG="ruby" ;;
  .php)                  LANG="php" ;;
  .dart)                 LANG="dart" ;;
  .ex|.exs)              LANG="elixir" ;;
  .scala|.sc)            LANG="scala" ;;
  *)                     exit 0 ;;  # Unsupported language, skip
esac

# --- Check language is in the allowed list ---
# FORGE_L0_LANGUAGES: "auto" = all supported, otherwise space-separated list
if [[ "${FORGE_L0_LANGUAGES:-auto}" != "auto" ]]; then
  # Normalize: the config uses forge language names (typescript, not tsx)
  _CHECK_LANG="$LANG"
  [[ "$_CHECK_LANG" == "tsx" ]] && _CHECK_LANG="typescript"
  [[ "$_CHECK_LANG" == "jsx" ]] && _CHECK_LANG="javascript"
  if ! echo "${FORGE_L0_LANGUAGES}" | grep -qw "$_CHECK_LANG"; then
    exit 0  # Language not in the configured list
  fi
fi

# --- Simulate the edit result ---
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
TEMP_FILE="$TEMP_DIR/$(basename "$FILE_PATH")"

"$_PY" "$SCRIPT_DIR/apply-edit-preview.py" \
  --tool-name "${TOOL_NAME}" \
  --tool-input "${TOOL_INPUT}" \
  --file-path "$FILE_PATH" \
  --output "$TEMP_FILE" 2>/dev/null || { _log_failure "skip:edit_preview_failed"; exit 0; }

[[ ! -f "$TEMP_FILE" ]] && exit 0

# --- Increment total checks counter ---
_increment_counter ".l0-total-checks"

# --- Run tree-sitter parse with timeout ---
TIMEOUT_MS="${FORGE_L0_TIMEOUT_MS:-500}"
# Convert ms to seconds for timeout command (minimum 1s for CLI granularity)
TIMEOUT_S=$(( (TIMEOUT_MS + 999) / 1000 ))
[[ "$TIMEOUT_S" -lt 1 ]] && TIMEOUT_S=1

PARSE_OUTPUT=""
if command -v timeout &>/dev/null; then
  PARSE_OUTPUT=$(timeout "${TIMEOUT_S}s" tree-sitter parse "$TEMP_FILE" 2>&1) || true
elif command -v gtimeout &>/dev/null; then
  # macOS with coreutils: gtimeout
  PARSE_OUTPUT=$(gtimeout "${TIMEOUT_S}s" tree-sitter parse "$TEMP_FILE" 2>&1) || true
else
  # No timeout command available, run without timeout
  PARSE_OUTPUT=$(tree-sitter parse "$TEMP_FILE" 2>&1) || true
fi

# --- Check for grammar-not-found errors ---
if echo "$PARSE_OUTPUT" | grep -qi "no language found\|unknown language\|could not determine"; then
  _log_failure "skip:grammar_missing_${LANG}"
  exit 0
fi

# --- Check for ERROR nodes ---
if echo "$PARSE_OUTPUT" | grep -q '(ERROR'; then
  _increment_counter ".l0-blocks"

  # Extract the first error location
  ERROR_LINE=$("$_PY" "$SCRIPT_DIR/extract-error.py" \
    --parse-output "$PARSE_OUTPUT" \
    --file "$TEMP_FILE" 2>/dev/null) || ERROR_LINE="(could not extract location)"

  # Map internal grammar names back to human-readable language names
  DISPLAY_LANG="$LANG"
  [[ "$DISPLAY_LANG" == "c_sharp" ]] && DISPLAY_LANG="C#"
  [[ "$DISPLAY_LANG" == "tsx" ]] && DISPLAY_LANG="TypeScript (TSX)"
  [[ "$DISPLAY_LANG" == "jsx" ]] && DISPLAY_LANG="JavaScript (JSX)"
  [[ "$DISPLAY_LANG" == "cpp" ]] && DISPLAY_LANG="C++"

  # Return error message — this blocks the edit
  cat <<EOF
SYNTAX ERROR — edit would produce invalid ${DISPLAY_LANG} syntax.

${ERROR_LINE}

The file would not parse after this edit. Please fix the syntax error and retry.
Hint: Check for missing brackets, unclosed strings, incorrect indentation, or mismatched delimiters.
EOF
  exit 1
fi

# Parse clean — allow the edit
exit 0
