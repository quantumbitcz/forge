#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# incremental-update.sh — Incremental Project Graph Updater
#
# Generates Cypher for incrementally updating the project graph based on
# git changes since the last full build.
#
# Usage:
#   ./shared/graph/incremental-update.sh --project-root /path/to/project
#
# Output: Cypher to stdout
# Side effects:
#   - Updates .forge/graph/.last-build-sha with current HEAD
#   - May exec build-project-graph.sh for full rebuild if no prior build
# ============================================================================

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../platform.sh
source "${PLUGIN_ROOT}/shared/platform.sh"

# Requires Bash 4.0+ (uses associative arrays)
require_bash4 "incremental-update.sh" || exit 1

PROJECT_ROOT=""
PROJECT_ID=""
COMPONENT=""

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="$2"
      shift 2
      ;;
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --component)
      COMPONENT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: incremental-update.sh --project-root /path/to/project [--project-id org/repo] [--component name]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo "Error: --project-root is required" >&2
  exit 1
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
  echo "Error: $PROJECT_ROOT is not a git repository" >&2
  exit 1
fi

# --- Helper: escape strings for Cypher ---
cypher_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\'/\\\'}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  printf '%s' "$s"
}

# Auto-derive project_id if not provided
if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
fi
# Escape project_id for safe Cypher embedding
PROJECT_ID="$(cypher_escape "$PROJECT_ID")"

if [[ -n "$COMPONENT" ]]; then
  COMPONENT_CYPHER="'$(cypher_escape "$COMPONENT")'"
else
  COMPONENT_CYPHER="null"
fi

# --- Ensure output directories ---
GRAPH_DIR="${PROJECT_ROOT}/.forge/graph"
mkdir -p "$GRAPH_DIR"

# --- Source file extensions (same as build-project-graph.sh) ---
SOURCE_EXTS='\.kt$|\.java$|\.ts$|\.tsx$|\.js$|\.jsx$|\.py$|\.go$|\.rs$|\.rb$|\.php$|\.ex$|\.exs$|\.scala$|\.dart$|\.swift$|\.cs$|\.c$|\.cc$|\.cpp$|\.cxx$|\.h$|\.hpp$'

# --- Check for last build SHA ---
LAST_BUILD_FILE="${GRAPH_DIR}/.last-build-sha"

if [[ ! -f "$LAST_BUILD_FILE" ]]; then
  echo "// No prior build found — executing full rebuild" >&2
  exec "${PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID" ${COMPONENT:+--component "$COMPONENT"}
fi

LAST_BUILD_SHA="$(tr -d '[:space:]' < "$LAST_BUILD_FILE")"

if [[ -z "$LAST_BUILD_SHA" || "$LAST_BUILD_SHA" == "unknown" || ! "$LAST_BUILD_SHA" =~ ^[0-9a-f]+$ ]]; then
  echo "// Invalid last build SHA — executing full rebuild" >&2
  exec "${PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID" ${COMPONENT:+--component "$COMPONENT"}
fi

# Verify the SHA still exists in the repo
if ! (cd "$PROJECT_ROOT" && git cat-file -e "$LAST_BUILD_SHA" 2>/dev/null); then
  echo "// Last build SHA ${LAST_BUILD_SHA} no longer in history — executing full rebuild" >&2
  exec "${PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID" ${COMPONENT:+--component "$COMPONENT"}
fi

CURRENT_SHA="$(cd "$PROJECT_ROOT" && git rev-parse HEAD)"

# --- If HEAD hasn't moved, nothing to do ---
if [[ "$LAST_BUILD_SHA" == "$CURRENT_SHA" ]]; then
  echo "// No changes since last build (${CURRENT_SHA})"
  exit 0
fi

# --- Get changed files ---
if ! CHANGES="$(cd "$PROJECT_ROOT" && git diff --name-status "${LAST_BUILD_SHA}..HEAD" 2>/dev/null)"; then
  echo "// git diff failed (shallow clone or corrupt history?) — executing full rebuild" >&2
  exec "${PLUGIN_ROOT}/shared/graph/build-project-graph.sh" --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID" ${COMPONENT:+--component "$COMPONENT"}
fi

if [[ -z "$CHANGES" ]]; then
  echo "// No file changes between ${LAST_BUILD_SHA} and ${CURRENT_SHA}"
  echo "$CURRENT_SHA" > "$LAST_BUILD_FILE"
  exit 0
fi

# --- Filter to source files only ---
SOURCE_CHANGES="$(echo "$CHANGES" | grep -E "$SOURCE_EXTS" || true)"

if [[ -z "$SOURCE_CHANGES" ]]; then
  echo "// No source file changes since last build"
  echo "$CURRENT_SHA" > "$LAST_BUILD_FILE"
  exit 0
fi

# cypher_escape defined above (before project_id escaping)

# --- Helper: determine language from extension ---
ext_to_lang() {
  local file="$1"
  case "$file" in
    *.kt|*.kts) echo "kotlin" ;;
    *.java)  echo "java" ;;
    *.ts|*.tsx) echo "typescript" ;;
    *.js|*.jsx) echo "javascript" ;;
    *.py)    echo "python" ;;
    *.go)    echo "go" ;;
    *.rs)    echo "rust" ;;
    *.rb)    echo "ruby" ;;
    *.php)   echo "php" ;;
    *.ex|*.exs) echo "elixir" ;;
    *.scala) echo "scala" ;;
    *.dart)  echo "dart" ;;
    *.swift) echo "swift" ;;
    *.cs|*.csx) echo "csharp" ;;
    *.c|*.h) echo "c" ;;
    *.cpp|*.cc|*.cxx|*.hpp) echo "cpp" ;;
    *)       echo "unknown" ;;
  esac
}

# --- Helper: get file size ---
file_size() {
  wc -c < "$PROJECT_ROOT/$1" 2>/dev/null | tr -d ' '
}

# --- Helper: get last modified date (YYYY-MM-DD) ---
# Delegates to portable_file_date from platform.sh (BSD stat → GNU stat+date → perl → python3 → git → today)
file_date() {
  portable_file_date "$PROJECT_ROOT/$1"
}

# --- Build file set for import resolution ---
declare -A FILE_SET=()
while IFS= read -r f; do
  FILE_SET["$f"]=1
done < <(cd "$PROJECT_ROOT" && git ls-files | grep -E "$SOURCE_EXTS" | sort)

# --- Helper: resolve a path and check if it exists in FILE_SET ---
resolve_file() {
  local candidate="$1"
  [[ -n "${FILE_SET[$candidate]:-}" ]] && echo "$candidate" && return
  for ext in .ts .tsx .js .jsx .kt .java .py .go .rs .rb .php .ex .exs .scala .dart .swift .cs .c .cpp .h .hpp; do
    [[ -n "${FILE_SET[${candidate}${ext}]:-}" ]] && echo "${candidate}${ext}" && return
  done
  for idx in /index.ts /index.tsx /index.js /index.jsx /mod.rs /lib.rs /__init__.py; do
    [[ -n "${FILE_SET[${candidate}${idx}]:-}" ]] && echo "${candidate}${idx}" && return
  done
  echo ""
}

# --- Import parsers (mirrors build-project-graph.sh) ---

parse_imports_ts() {
  local file="$1"
  grep -oE "(from|import) +['\"](\./|\.\./)[^'\"]+['\"]" "$PROJECT_ROOT/$file" 2>/dev/null | \
    sed -E "s/(from|import) +['\"]//; s/['\"]$//" | while IFS= read -r imp; do
      [[ -z "$imp" ]] && continue
      local resolved
      resolved="$(portable_normalize_path "$(dirname "$file")/$imp")"
      local target
      target="$(resolve_file "$resolved")"
      [[ -n "$target" ]] && echo "$target"
    done
}

parse_imports_python() {
  local file="$1"
  grep -oE "^from +[a-zA-Z_][a-zA-Z0-9_.]*" "$PROJECT_ROOT/$file" 2>/dev/null | \
    sed 's/^from //' | while IFS= read -r module; do
      local path_candidate="${module//./\/}"
      local target
      target="$(resolve_file "$path_candidate")"
      [[ -z "$target" ]] && target="$(resolve_file "${path_candidate}/__init__")"
      [[ -n "$target" ]] && echo "$target"
    done
}

parse_imports_kotlin_java() {
  local file="$1"
  grep -oE "^import +[a-zA-Z][a-zA-Z0-9_.]*" "$PROJECT_ROOT/$file" 2>/dev/null | \
    sed 's/^import //' | while IFS= read -r fqcn; do
      local pkg_path="${fqcn%.*}"
      local class_name="${fqcn##*.}"
      pkg_path="${pkg_path//./\/}"
      local target=""
      for base in "src/main/kotlin" "src/main/java" "src" "app/src/main/kotlin" "app/src/main/java"; do
        local candidate="${base}/${pkg_path}/${class_name}"
        target="$(resolve_file "$candidate")"
        [[ -n "$target" ]] && break
      done
      [[ -n "$target" ]] && echo "$target"
    done
}

parse_imports_go() {
  local file="$1"
  local mod_path=""
  if [[ -f "$PROJECT_ROOT/go.mod" ]]; then
    mod_path="$(head -1 "$PROJECT_ROOT/go.mod" | sed 's/^module //' | tr -d '[:space:]')"
  fi
  [[ -z "$mod_path" ]] && return
  # Escape dots in module path for grep regex
  local mod_pattern="${mod_path//./\\.}"
  grep -oE "\"${mod_pattern}/[^\"]+\"" "$PROJECT_ROOT/$file" 2>/dev/null | \
    tr -d '"' | while IFS= read -r imp; do
      local rel="${imp#"${mod_path}"/}"
      local target
      target="$(resolve_file "$rel")"
      [[ -n "$target" ]] && echo "$target"
    done
}

parse_imports_rust() {
  local file="$1"
  grep -oE "use crate::[a-zA-Z_][a-zA-Z0-9_:]*" "$PROJECT_ROOT/$file" 2>/dev/null | \
    sed 's/^use crate:://' | while IFS= read -r mod_path; do
      local path_candidate="src/${mod_path//::///}"
      local target
      target="$(resolve_file "$path_candidate")"
      [[ -n "$target" ]] && echo "$target"
    done
}

parse_imports_ruby() {
  local file="$1"
  grep -oE "require_relative +['\"][^'\"]+['\"]" "$PROJECT_ROOT/$file" 2>/dev/null | \
    sed -E "s/require_relative +['\"]//; s/['\"]$//" | while IFS= read -r imp; do
      [[ -z "$imp" ]] && continue
      local candidate
      candidate="$(portable_normalize_path "$(dirname "$file")/$imp")"
      local target
      target="$(resolve_file "$candidate")"
      [[ -n "$target" ]] && echo "$target"
    done
}

parse_imports_php() {
  local file="$1"
  grep -oE "^use +[A-Z][a-zA-Z0-9\\\\]*" "$PROJECT_ROOT/$file" 2>/dev/null | \
    sed 's/^use //' | while IFS= read -r ns; do
      local path_candidate="src/${ns//\\//}"
      local target
      target="$(resolve_file "$path_candidate")"
      [[ -n "$target" ]] && echo "$target"
    done
}

parse_imports_elixir() {
  local file="$1"
  grep -oE "alias +[A-Z][a-zA-Z0-9_.]*" "$PROJECT_ROOT/$file" 2>/dev/null | \
    sed 's/^alias //' | while IFS= read -r mod; do
      [[ -z "$mod" ]] && continue
      local path_candidate=""
      # Try Python for accurate CamelCase → snake_case conversion
      if command -v "$FORGE_PYTHON" &>/dev/null; then
        path_candidate="$("$FORGE_PYTHON" -c "
import re, sys
mod = sys.argv[1]
parts = mod.split('.')
snake_parts = []
for p in parts:
    s = re.sub(r'([A-Z])', r'_\1', p).lower().lstrip('_')
    snake_parts.append(s)
print('lib/' + '/'.join(snake_parts))
" "$mod" 2>/dev/null || echo "")"
      fi
      # Bash fallback: lowercase and insert underscores before capitals (Bash 3.2+)
      if [[ -z "$path_candidate" ]]; then
        local result="lib"
        local IFS='.' part
        for part in $mod; do
          local snake=""
          local i char lower prev_upper=false
          for ((i = 0; i < ${#part}; i++)); do
            char="${part:$i:1}"
            if [[ "$char" =~ [A-Z] ]]; then
              [[ $i -gt 0 && "$prev_upper" == false ]] && snake="${snake}_"
              lower="$(printf '%s' "$char" | tr '[:upper:]' '[:lower:]')"
              snake="${snake}${lower}"
              prev_upper=true
            else
              snake="${snake}${char}"
              prev_upper=false
            fi
          done
          result="${result}/${snake}"
        done
        path_candidate="$result"
      fi
      local target
      target="$(resolve_file "$path_candidate")"
      [[ -n "$target" ]] && echo "$target"
    done
}

parse_imports_c_cpp() {
  local file="$1"
  grep -oE '#include +"[^"]+"' "$PROJECT_ROOT/$file" 2>/dev/null | \
    sed -E 's/#include +"//; s/"$//' | while IFS= read -r inc; do
      local dir
      dir="$(dirname "$file")"
      local target
      target="$(resolve_file "${dir}/${inc}")"
      [[ -z "$target" ]] && target="$(resolve_file "$inc")"
      [[ -n "$target" ]] && echo "$target"
    done
}

parse_imports_csharp() {
  local file="$1"
  grep -oE "^using +[A-Z][a-zA-Z0-9_.]*" "$PROJECT_ROOT/$file" 2>/dev/null | \
    sed 's/^using //' | while IFS= read -r ns; do
      local path_candidate="${ns//./\/}"
      local target
      target="$(resolve_file "$path_candidate")"
      [[ -n "$target" ]] && echo "$target"
    done
}

# --- Helper: emit Cypher for creating a file node + import edges ---
emit_file_create() {
  local file="$1"
  [[ -f "$PROJECT_ROOT/$file" ]] || return 0  # Skip deleted files
  local lang size mod_date
  lang="$(ext_to_lang "$file")"
  size="$(file_size "$file")"
  mod_date="$(file_date "$file")"

  echo "CREATE (:ProjectFile {path: '$(cypher_escape "$file")', language: '${lang}', size: ${size}, last_modified: '${mod_date}', project_id: '${PROJECT_ID}', component: ${COMPONENT_CYPHER}});"

  # Parse imports and emit edges
  local import_targets=""
  case "$lang" in
    typescript|javascript) import_targets="$(parse_imports_ts "$file" 2>/dev/null)" ;;
    python)                import_targets="$(parse_imports_python "$file" 2>/dev/null)" ;;
    kotlin|java)           import_targets="$(parse_imports_kotlin_java "$file" 2>/dev/null)" ;;
    go)                    import_targets="$(parse_imports_go "$file" 2>/dev/null)" ;;
    rust)                  import_targets="$(parse_imports_rust "$file" 2>/dev/null)" ;;
    ruby)                  import_targets="$(parse_imports_ruby "$file" 2>/dev/null)" ;;
    php)                   import_targets="$(parse_imports_php "$file" 2>/dev/null)" ;;
    elixir)                import_targets="$(parse_imports_elixir "$file" 2>/dev/null)" ;;
    c|cpp)                 import_targets="$(parse_imports_c_cpp "$file" 2>/dev/null)" ;;
    csharp)                import_targets="$(parse_imports_csharp "$file" 2>/dev/null)" ;;
  esac

  if [[ -n "$import_targets" ]]; then
    declare -A seen_local=()
    while IFS= read -r target; do
      [[ -z "$target" || "$target" == "$file" ]] && continue
      if [[ -z "${seen_local[$target]:-}" ]]; then
        seen_local["$target"]=1
        echo "MATCH (a:ProjectFile {path: '$(cypher_escape "$file")', project_id: '${PROJECT_ID}'}), (b:ProjectFile {path: '$(cypher_escape "$target")', project_id: '${PROJECT_ID}'}) CREATE (a)-[:IMPORTS]->(b);"
      fi
    done <<< "$import_targets"
  fi

  # BELONGS_TO package edge
  local dir
  dir="$(dirname "$file")"
  if [[ "$dir" != "." ]]; then
    echo "MATCH (f:ProjectFile {path: '$(cypher_escape "$file")', project_id: '${PROJECT_ID}'}), (p:ProjectPackage {path: '$(cypher_escape "$dir")', project_id: '${PROJECT_ID}'}) CREATE (f)-[:BELONGS_TO]->(p);"
  fi
}

# --- Helper: emit Cypher for deleting a file node ---
emit_file_delete() {
  local file="$1"
  echo "MATCH (f:ProjectFile {path: '$(cypher_escape "$file")', project_id: '${PROJECT_ID}'}) DETACH DELETE f;"
}

# ============================================================================
# Emit header
# ============================================================================

echo "// ===================================="
echo "// Incremental Graph Update"
echo "// Generated by incremental-update.sh"
echo "// Project: ${PROJECT_ROOT}"
echo "// Project ID: ${PROJECT_ID}"
echo "// Component: ${COMPONENT:-<none>}"
echo "// Base SHA: ${LAST_BUILD_SHA}"
echo "// Head SHA: ${CURRENT_SHA}"
echo "// ===================================="
echo ""

# ============================================================================
# Process each change
# ============================================================================

ADDED=0
MODIFIED=0
DELETED=0
RENAMED=0

echo "// --- Transaction boundary: wrap in :begin/:commit for atomicity ---"
echo ":begin"
echo ""
echo "// --- Deleted / Modified (detach-delete phase) ---"
while IFS=$'\t' read -r status old_path new_path; do
  case "$status" in
    D)
      emit_file_delete "$old_path"
      ((DELETED++)) || true
      ;;
    M)
      emit_file_delete "$old_path"
      ((MODIFIED++)) || true
      ;;
    R*)
      # Rename: delete old path (new_path has the rename target)
      emit_file_delete "$old_path"
      ((RENAMED++)) || true
      ;;
  esac
done <<< "$SOURCE_CHANGES"
echo ""

echo "// --- Added / Modified / Renamed (create phase) ---"
while IFS=$'\t' read -r status old_path new_path; do
  case "$status" in
    A)
      emit_file_create "$old_path"
      ((ADDED++)) || true
      ;;
    M)
      emit_file_create "$old_path"
      ;;
    R*)
      # Rename: create the new path
      if [[ -n "$new_path" ]]; then
        emit_file_create "$new_path"
      fi
      ;;
  esac
done <<< "$SOURCE_CHANGES"
echo ""

# ============================================================================
# Update last build SHA
# ============================================================================

echo "$CURRENT_SHA" > "$LAST_BUILD_FILE"

echo ":commit"
echo ""
echo "// --- Summary ---"
echo "// Added: ${ADDED}, Modified: ${MODIFIED}, Deleted: ${DELETED}, Renamed: ${RENAMED}"
echo "// Updated .last-build-sha to ${CURRENT_SHA}"
