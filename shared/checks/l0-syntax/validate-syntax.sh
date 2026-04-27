#!/usr/bin/env bash
set -euo pipefail

# Self-enforcing timeout — mirrors hooks.json value
_HOOK_TIMEOUT="${FORGE_HOOK_TIMEOUT:-5}"
if [[ "${_HOOK_TIMEOUT_ACTIVE:-}" != "1" ]]; then
  export _HOOK_TIMEOUT_ACTIVE=1
  if command -v timeout &>/dev/null; then
    timeout "$_HOOK_TIMEOUT" "$0" "$@" || true
    exit 0
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$_HOOK_TIMEOUT" "$0" "$@" || true
    exit 0
  fi
  # No timeout command available — continue without enforcement
fi

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
# Appends a JSON row to .forge/.hook-failures.jsonl (best-effort, never fails).
# Schema mirrors shared/schemas/hook-failures.schema.json.
# Inlined (not sourced from engine.sh) to avoid hook startup cost.
_handle_failure() {
  # $1 hook_name, $2 matcher, $3 exit_code, $4 stderr_excerpt, $5 duration_ms
  local log_dir="${FORGE_DIR:-.forge}"
  mkdir -p "$log_dir" 2>/dev/null || return 0
  local log_file="${log_dir}/.hook-failures.jsonl"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  local cwd="${PWD//\"/\\\"}"
  local stderr_ex="${4:0:2048}"
  stderr_ex="${stderr_ex//$'\n'/\\n}"
  stderr_ex="${stderr_ex//\"/\\\"}"
  printf '{"schema":1,"ts":"%s","hook_name":"%s","matcher":"%s","exit_code":%s,"stderr_excerpt":"%s","duration_ms":%s,"cwd":"%s"}\n' \
    "$ts" "$1" "$2" "$3" "$stderr_ex" "$5" "$cwd" \
    >> "$log_file" 2>/dev/null || true
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
  _handle_failure "validate-syntax.sh" "PreToolUse" 0 "skip:tree-sitter_not_installed | ${FILE_PATH:-unknown}" 0
  exit 0
fi

# --- Check python availability ---
_PY="python3"
command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then
  _handle_failure "validate-syntax.sh" "PreToolUse" 0 "skip:python_not_found | ${FILE_PATH:-unknown}" 0
  exit 0
fi

# --- Extract file path from TOOL_INPUT ---
FILE_PATH=""
TOOL_NAME="${TOOL_NAME:-}"
FILE_PATH=$("$_PY" -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d.get('file_path', ''))
" <<< "${TOOL_INPUT:-}" 2>/dev/null) || { _handle_failure "validate-syntax.sh" "PreToolUse" 0 "skip:json_parse_failed | ${FILE_PATH:-unknown}" 0; exit 0; }

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
  --output "$TEMP_FILE" 2>/dev/null || { _handle_failure "validate-syntax.sh" "PreToolUse" 0 "skip:edit_preview_failed | ${FILE_PATH:-unknown}" 0; exit 0; }

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
  # MacOS with coreutils: gtimeout
  PARSE_OUTPUT=$(gtimeout "${TIMEOUT_S}s" tree-sitter parse "$TEMP_FILE" 2>&1) || true
else
  # No timeout command available, run without timeout
  PARSE_OUTPUT=$(tree-sitter parse "$TEMP_FILE" 2>&1) || true
fi

# --- Check for grammar-not-found errors ---
if echo "$PARSE_OUTPUT" | grep -qi "no language found\|unknown language\|could not determine"; then
  _handle_failure "validate-syntax.sh" "PreToolUse" 0 "skip:grammar_missing_${LANG} | ${FILE_PATH:-unknown}" 0
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
