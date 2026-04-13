#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# incremental-code-graph.sh — Incremental Code Graph Updater
#
# Compares current file hashes against stored hashes in .forge/code-graph.db.
# Only re-parses changed/new files, removes deleted file nodes.
#
# Called by the orchestrator after IMPLEMENT stage for efficient graph updates.
#
# Usage:
#   ./shared/graph/incremental-code-graph.sh --project-root /path/to/project \
#       [--project-id org/repo] [--component api]
#
# Output: Summary to stderr. Exit 0 on success or graceful degradation.
# ============================================================================

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../platform.sh
source "${PLUGIN_ROOT}/shared/platform.sh"

require_bash4 "incremental-code-graph.sh" || exit 1

# ── Argument parsing ─────────────────────────────────────────────────────────

PROJECT_ROOT=""
PROJECT_ID=""
COMPONENT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --project-id)   PROJECT_ID="$2"; shift 2 ;;
    --component)    COMPONENT="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: incremental-code-graph.sh --project-root /path [--project-id id] [--component name]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo "Error: --project-root is required" >&2
  exit 1
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
DB_PATH="${PROJECT_ROOT}/.forge/code-graph.db"

# ── Graceful degradation ────────────────────────────────────────────────────

if [[ ! -f "$DB_PATH" ]]; then
  echo "[code-graph-incremental] No code-graph.db found. Running full build." >&2
  exec "${PLUGIN_ROOT}/shared/graph/build-code-graph.sh" \
    --project-root "$PROJECT_ROOT" \
    ${PROJECT_ID:+--project-id "$PROJECT_ID"} \
    ${COMPONENT:+--component "$COMPONENT"}
fi

if ! command -v sqlite3 &>/dev/null; then
  echo "[code-graph-incremental] WARNING: sqlite3 not found. Skipping update." >&2
  exit 0
fi

if ! command -v tree-sitter &>/dev/null; then
  echo "[code-graph-incremental] INFO: tree-sitter not found. Skipping update." >&2
  exit 0
fi

# ── Check if graph is current ───────────────────────────────────────────────

LAST_BUILD_SHA="$(sqlite3 "$DB_PATH" "SELECT value FROM schema_meta WHERE key='last_build_sha';" 2>/dev/null || echo "")"
CURRENT_SHA="$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo "unknown")"

if [[ "$LAST_BUILD_SHA" == "$CURRENT_SHA" && "$CURRENT_SHA" != "unknown" ]]; then
  echo "[code-graph-incremental] Graph is current (${CURRENT_SHA:0:8}). No update needed." >&2
  exit 0
fi

# ── Determine changed files ─────────────────────────────────────────────────

SOURCE_EXTS='\.kt$|\.kts$|\.java$|\.ts$|\.tsx$|\.js$|\.jsx$|\.py$|\.go$|\.rs$|\.swift$|\.c$|\.h$|\.cs$|\.rb$|\.php$|\.dart$|\.ex$|\.exs$|\.scala$|\.cpp$|\.cc$|\.cxx$|\.hpp$'
CHANGED_FILES=()
DELETED_FILES=()

# Method 1: Use git diff if we have a valid last build SHA
if [[ -n "$LAST_BUILD_SHA" && "$LAST_BUILD_SHA" != "unknown" ]]; then
  if (cd "$PROJECT_ROOT" && git cat-file -e "$LAST_BUILD_SHA" 2>/dev/null); then
    while IFS=$'\t' read -r status file_path new_path; do
      [[ -z "$file_path" ]] && continue
      # Filter to source files
      if echo "$file_path" | grep -qE "$SOURCE_EXTS"; then
        case "$status" in
          D)  DELETED_FILES+=("$file_path") ;;
          A|M) CHANGED_FILES+=("$file_path") ;;
          R*) DELETED_FILES+=("$file_path")
              [[ -n "$new_path" ]] && CHANGED_FILES+=("$new_path") ;;
        esac
      fi
      # Handle renamed files' new paths
      if [[ -n "$new_path" ]] && echo "$new_path" | grep -qE "$SOURCE_EXTS"; then
        case "$status" in
          R*) ;; # Already handled above
        esac
      fi
    done < <(cd "$PROJECT_ROOT" && git diff --name-status "${LAST_BUILD_SHA}..HEAD" 2>/dev/null || true)
  fi
fi

# Method 2: If git diff didn't work, compare all file hashes
if [[ ${#CHANGED_FILES[@]} -eq 0 && ${#DELETED_FILES[@]} -eq 0 ]]; then
  echo "[code-graph-incremental] Git diff unavailable. Comparing file hashes." >&2

  # SHA256 helper
  file_sha256() {
    if command -v shasum &>/dev/null; then
      shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
    elif command -v sha256sum &>/dev/null; then
      sha256sum "$1" 2>/dev/null | cut -d' ' -f1
    elif [[ -n "$FORGE_PYTHON" ]]; then
      "$FORGE_PYTHON" -c "
import hashlib, sys
with open(sys.argv[1], 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())
" "$1" 2>/dev/null
    fi
  }

  # Get all current source files
  declare -A CURRENT_FILES=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    CURRENT_FILES["$f"]=1
  done < <(cd "$PROJECT_ROOT" && git ls-files 2>/dev/null | grep -E "$SOURCE_EXTS" || true)

  # Check stored hashes
  while IFS='|' read -r stored_path stored_hash; do
    [[ -z "$stored_path" ]] && continue
    if [[ -z "${CURRENT_FILES[$stored_path]:-}" ]]; then
      DELETED_FILES+=("$stored_path")
    else
      local_hash="$(file_sha256 "${PROJECT_ROOT}/${stored_path}" || echo "")"
      if [[ "$local_hash" != "$stored_hash" ]]; then
        CHANGED_FILES+=("$stored_path")
      fi
      unset "CURRENT_FILES[$stored_path]"
    fi
  done < <(sqlite3 -separator '|' "$DB_PATH" "SELECT file_path, content_hash FROM file_hashes;" 2>/dev/null || true)

  # Remaining files in CURRENT_FILES are new
  for new_file in "${!CURRENT_FILES[@]}"; do
    CHANGED_FILES+=("$new_file")
  done
fi

TOTAL_CHANGES=$(( ${#CHANGED_FILES[@]} + ${#DELETED_FILES[@]} ))

if [[ $TOTAL_CHANGES -eq 0 ]]; then
  echo "[code-graph-incremental] No changes detected. Updating SHA." >&2
  sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO schema_meta VALUES ('last_build_sha', '${CURRENT_SHA}');" 2>/dev/null
  exit 0
fi

echo "[code-graph-incremental] Changes detected: ${#CHANGED_FILES[@]} modified/new, ${#DELETED_FILES[@]} deleted." >&2

# ── Delegate to build script in incremental mode ────────────────────────────

# For small change sets, use the build script's incremental mode
# For large change sets (>50% of files), do a full rebuild
TOTAL_FILES="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM file_hashes;" 2>/dev/null || echo "0")"

if [[ $TOTAL_FILES -gt 0 && $TOTAL_CHANGES -gt $(( TOTAL_FILES / 2 )) ]]; then
  echo "[code-graph-incremental] Large change set (${TOTAL_CHANGES}/${TOTAL_FILES}). Running full rebuild." >&2
  exec "${PLUGIN_ROOT}/shared/graph/build-code-graph.sh" \
    --project-root "$PROJECT_ROOT" \
    ${PROJECT_ID:+--project-id "$PROJECT_ID"} \
    ${COMPONENT:+--component "$COMPONENT"}
fi

# Use incremental mode
exec "${PLUGIN_ROOT}/shared/graph/build-code-graph.sh" \
  --project-root "$PROJECT_ROOT" \
  ${PROJECT_ID:+--project-id "$PROJECT_ID"} \
  ${COMPONENT:+--component "$COMPONENT"} \
  --incremental
