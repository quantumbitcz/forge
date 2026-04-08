#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# build-project-graph.sh — Project Codebase Graph Builder
#
# Scans a consuming project's codebase and outputs Cypher statements to stdout
# for creating the project portion of the Neo4j knowledge graph.
#
# Usage:
#   ./shared/graph/build-project-graph.sh --project-root /path/to/project
#
# Output: Cypher to stdout
# Side effects:
#   - Creates .forge/graph/ if needed
#   - Writes git SHA to .forge/graph/.last-build-sha
#   - Writes unresolved imports to .forge/graph/.unresolved-imports.log
# ============================================================================

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../platform.sh
source "${PLUGIN_ROOT}/shared/platform.sh"

# Requires Bash 4.0+ (uses associative arrays)
require_bash4 "build-project-graph.sh" || exit 1
# _glob_exists is provided by platform.sh (sourced above)

if [[ -z "$FORGE_PYTHON" ]]; then
  echo "[build-project-graph] WARNING: No Python interpreter found. Graph build may produce incomplete results." >&2
fi

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
      echo "Usage: build-project-graph.sh --project-root /path/to/project [--project-id org/repo] [--component api]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo "Error: --project-root is required" >&2
  exit 1
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

# --- Helper: escape strings for Cypher (defined early for project_id escaping) ---
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
if [[ -z "${PROJECT_ID:-}" ]]; then
  PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
fi
# Escape project_id for safe Cypher embedding (handles paths with single quotes).
# NOTE: PROJECT_ID is pre-escaped here — do NOT pass it through cypher_escape() again.
PROJECT_ID="$(cypher_escape "$PROJECT_ID")"
COMPONENT="${COMPONENT:-}"

# Cypher-safe component value (escaped for Cypher)
if [[ -n "$COMPONENT" ]]; then
  COMPONENT_CYPHER="'$(cypher_escape "$COMPONENT")'"
else
  COMPONENT_CYPHER="null"
fi

if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
  echo "Error: $PROJECT_ROOT is not a git repository" >&2
  exit 1
fi

# --- Ensure output directories ---
GRAPH_DIR="${PROJECT_ROOT}/.forge/graph"
if ! mkdir -p "$GRAPH_DIR" 2>/dev/null; then
  echo "Error: Cannot create $GRAPH_DIR — check directory permissions" >&2
  exit 1
fi
if [[ ! -w "$GRAPH_DIR" ]]; then
  echo "Error: $GRAPH_DIR is not writable" >&2
  exit 1
fi

UNRESOLVED_LOG="${GRAPH_DIR}/.unresolved-imports.log"
: > "$UNRESOLVED_LOG"

# --- Source file extensions ---
SOURCE_EXTS='\.kt$|\.java$|\.ts$|\.tsx$|\.js$|\.jsx$|\.py$|\.go$|\.rs$|\.rb$|\.php$|\.ex$|\.exs$|\.scala$|\.dart$|\.swift$|\.cs$|\.c$|\.cc$|\.cpp$|\.cxx$|\.h$|\.hpp$'

# --- Collect all source files into an associative array for fast lookups ---
declare -A FILE_SET=()
declare -a ALL_FILES=()

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  ALL_FILES+=("$f")
  FILE_SET["$f"]=1
done < <(cd "$PROJECT_ROOT" && git ls-files | grep -E "$SOURCE_EXTS" | sort || true)

# cypher_escape defined above (before project_id escaping)

# --- Helper: get file size (returns 0 if file is unreadable/missing) ---
file_size() {
  local sz
  sz=$(wc -c < "$PROJECT_ROOT/$1" 2>/dev/null | tr -d ' ')
  printf '%s' "${sz:-0}"
}

# --- Helper: get last modified date (YYYY-MM-DD) ---
# Delegates to portable_file_date from platform.sh (BSD stat → GNU stat+date → perl → python3 → git → today)
file_date() {
  portable_file_date "$PROJECT_ROOT/$1"
}

# --- Helper: determine language from extension ---
ext_to_lang() {
  local file="$1"
  case "$file" in
    *.kt|*.kts)  echo "kotlin" ;;
    *.java)     echo "java" ;;
    *.ts|*.tsx)  echo "typescript" ;;
    *.js|*.jsx)  echo "javascript" ;;
    *.py)       echo "python" ;;
    *.go)       echo "go" ;;
    *.rs)       echo "rust" ;;
    *.rb)       echo "ruby" ;;
    *.php)      echo "php" ;;
    *.ex|*.exs)  echo "elixir" ;;
    *.scala)    echo "scala" ;;
    *.dart)     echo "dart" ;;
    *.swift)    echo "swift" ;;
    *.cs|*.csx)  echo "csharp" ;;
    *.c|*.h)     echo "c" ;;
    *.cpp|*.cc|*.cxx|*.hpp) echo "cpp" ;;
    *)          echo "unknown" ;;
  esac
}

# --- Helper: normalize a path (remove ../ ./ and // segments) ---
# Delegates to portable_normalize_path from platform.sh
normalize_path() {
  portable_normalize_path "$1"
}

# --- Helper: resolve a path and check if it exists in FILE_SET ---
# Returns the matched file path or empty string
resolve_file() {
  local candidate="$1"
  # Try exact match
  if [[ -n "${FILE_SET[$candidate]:-}" ]]; then echo "$candidate"; return; fi
  # Try with common extensions
  local ext
  for ext in .ts .tsx .js .jsx .kt .java .py .go .rs .rb .php .ex .exs .scala .dart .swift .cs .c .cpp .h .hpp; do
    if [[ -n "${FILE_SET[${candidate}${ext}]:-}" ]]; then echo "${candidate}${ext}"; return; fi
  done
  # Try as directory index
  local idx
  for idx in /index.ts /index.tsx /index.js /index.jsx /mod.rs /lib.rs /__init__.py; do
    if [[ -n "${FILE_SET[${candidate}${idx}]:-}" ]]; then echo "${candidate}${idx}"; return; fi
  done
  echo ""
}

# --- Helper: safe grep that returns empty instead of failing ---
sgrep() {
  grep "$@" || true
}

# ============================================================================
# Step 1: Detect language from manifest files
# ============================================================================

detect_languages() {
  [[ -f "$PROJECT_ROOT/package.json" ]] && echo "typescript"
  [[ -f "$PROJECT_ROOT/build.gradle.kts" ]] && echo "kotlin"
  if [[ -f "$PROJECT_ROOT/build.gradle" && ! -f "$PROJECT_ROOT/build.gradle.kts" ]]; then
    echo "java"
  fi
  [[ -f "$PROJECT_ROOT/Cargo.toml" ]] && echo "rust"
  [[ -f "$PROJECT_ROOT/go.mod" ]] && echo "go"
  [[ -f "$PROJECT_ROOT/requirements.txt" || -f "$PROJECT_ROOT/pyproject.toml" ]] && echo "python"
  [[ -f "$PROJECT_ROOT/Gemfile" ]] && echo "ruby"
  [[ -f "$PROJECT_ROOT/composer.json" ]] && echo "php"
  [[ -f "$PROJECT_ROOT/mix.exs" ]] && echo "elixir"
  [[ -f "$PROJECT_ROOT/build.sbt" ]] && echo "scala"
  [[ -f "$PROJECT_ROOT/pubspec.yaml" ]] && echo "dart"
  [[ -f "$PROJECT_ROOT/Package.swift" ]] && echo "swift"
  if _glob_exists "$PROJECT_ROOT"/*.csproj || _glob_exists "$PROJECT_ROOT"/*.sln; then
    echo "csharp"
  fi
  if [[ -f "$PROJECT_ROOT/CMakeLists.txt" || -f "$PROJECT_ROOT/Makefile" ]]; then
    echo "c"
  fi
  true  # ensure success exit
}

# ============================================================================
# Step 2-3: Import parsing functions
# ============================================================================

parse_imports_ts() {
  local file="$1"
  # Match: import ... from './...' or import ... from '../...' and also import './...'
  sgrep -oE "(from|import) +['\"](\./|\.\./)[^'\"]+['\"]" "$PROJECT_ROOT/$file" | \
    sed -E "s/(from|import) +['\"]//; s/['\"]$//" | while IFS= read -r imp; do
      [[ -z "$imp" ]] && continue
      local resolved
      resolved="$(normalize_path "$(dirname "$file")/$imp")"
      local target
      target="$(resolve_file "$resolved")"
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:${imp}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

parse_imports_python() {
  local file="$1"
  # from X.Y.Z import ... => X/Y/Z
  sgrep -oE "^from +[a-zA-Z_][a-zA-Z0-9_.]*" "$PROJECT_ROOT/$file" | \
    sed 's/^from //' | while IFS= read -r module; do
      [[ -z "$module" ]] && continue
      local path_candidate="${module//./\/}"
      local target
      target="$(resolve_file "$path_candidate")"
      if [[ -z "$target" ]]; then
        target="$(resolve_file "${path_candidate}/__init__")"
      fi
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:${module}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

parse_imports_kotlin_java() {
  local file="$1"
  # import com.example.foo.Bar
  sgrep -oE "^import +[a-zA-Z][a-zA-Z0-9_.]*" "$PROJECT_ROOT/$file" | \
    sed 's/^import //' | while IFS= read -r fqcn; do
      [[ -z "$fqcn" ]] && continue
      local pkg_path="${fqcn%.*}"
      local class_name="${fqcn##*.}"
      pkg_path="${pkg_path//./\/}"

      local target="" base candidate
      for base in "src/main/kotlin" "src/main/java" "src" "app/src/main/kotlin" "app/src/main/java"; do
        candidate="${base}/${pkg_path}/${class_name}"
        target="$(resolve_file "$candidate")"
        [[ -n "$target" ]] && break
      done
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:${fqcn}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

parse_imports_go() {
  local file="$1"
  local mod_path=""
  if [[ -f "$PROJECT_ROOT/go.mod" ]]; then
    mod_path="$(head -1 "$PROJECT_ROOT/go.mod" | sed 's/^module //' | tr -d ' ')"
  fi
  [[ -z "$mod_path" ]] && return 0

  # Escape dots in mod_path for grep
  local mod_pattern="${mod_path//./\\.}"
  sgrep -oE "\"${mod_pattern}/[^\"]+\"" "$PROJECT_ROOT/$file" | \
    tr -d '"' | while IFS= read -r imp; do
      [[ -z "$imp" ]] && continue
      local rel="${imp#${mod_path}/}"
      local target
      target="$(resolve_file "$rel")"
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:${imp}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

parse_imports_rust() {
  local file="$1"
  # use crate::services::user
  sgrep -oE "use crate::[a-zA-Z_][a-zA-Z0-9_:]*" "$PROJECT_ROOT/$file" | \
    sed 's/^use crate:://' | while IFS= read -r mod_path; do
      [[ -z "$mod_path" ]] && continue
      local path_candidate="src/${mod_path//::///}"
      local target
      target="$(resolve_file "$path_candidate")"
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:crate::${mod_path}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

parse_imports_ruby() {
  local file="$1"
  # require_relative 'services/user_service'
  sgrep -oE "require_relative +['\"][^'\"]+['\"]" "$PROJECT_ROOT/$file" | \
    sed -E "s/require_relative +['\"]//; s/['\"]$//" | while IFS= read -r imp; do
      [[ -z "$imp" ]] && continue
      local candidate
      candidate="$(normalize_path "$(dirname "$file")/$imp")"
      local target
      target="$(resolve_file "$candidate")"
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:${imp}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

parse_imports_php() {
  local file="$1"
  # use App\Services\UserService
  sgrep -oE "^use +[A-Z][a-zA-Z0-9\\\\]*" "$PROJECT_ROOT/$file" | \
    sed 's/^use //' | while IFS= read -r ns; do
      [[ -z "$ns" ]] && continue
      local path_candidate="src/${ns//\\//}"
      local target
      target="$(resolve_file "$path_candidate")"
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:${ns}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

parse_imports_elixir() {
  local file="$1"
  # alias MyApp.UserService
  sgrep -oE "alias +[A-Z][a-zA-Z0-9_.]*" "$PROJECT_ROOT/$file" | \
    sed 's/^alias //' | while IFS= read -r mod; do
      [[ -z "$mod" ]] && continue
      local path_candidate
      if [[ -n "$FORGE_PYTHON" ]]; then
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
      else
        path_candidate=""
      fi
      [[ -z "$path_candidate" ]] && continue
      local target
      target="$(resolve_file "$path_candidate")"
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:${mod}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

parse_imports_c_cpp() {
  local file="$1"
  # #include "services/user.h" (only quoted includes, not angle-bracket)
  sgrep -oE '#include +"[^"]+"' "$PROJECT_ROOT/$file" | \
    sed -E 's/#include +"//; s/"$//' | while IFS= read -r inc; do
      [[ -z "$inc" ]] && continue
      local dir target
      dir="$(dirname "$file")"
      target="$(resolve_file "$(normalize_path "${dir}/${inc}")")"
      if [[ -z "$target" ]]; then
        target="$(resolve_file "$inc")"
      fi
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:${inc}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

parse_imports_csharp() {
  local file="$1"
  # using MyApp.Services
  sgrep -oE "^using +[A-Z][a-zA-Z0-9_.]*" "$PROJECT_ROOT/$file" | \
    sed 's/^using //' | while IFS= read -r ns; do
      [[ -z "$ns" ]] && continue
      local path_candidate="${ns//./\/}"
      local target
      target="$(resolve_file "$path_candidate")"
      if [[ -n "$target" ]]; then
        echo "$target"
      else
        echo "${file}:${ns}" >> "$UNRESOLVED_LOG"
      fi
    done
  true
}

# ============================================================================
# Emit header
# ============================================================================

echo "// ===================================="
echo "// Project Knowledge Graph"
echo "// Generated by build-project-graph.sh"
echo "// Project: ${PROJECT_ROOT}"
echo "// Project ID: ${PROJECT_ID}"
echo "// Component: ${COMPONENT:-<none>}"
echo "// ===================================="
echo ""

# ============================================================================
# Step 0: Delete existing project nodes for this project_id (scoped)
# ============================================================================

echo "// --- Scoped Deletion ---"
{
  component_filter=""
  if [[ -n "$COMPONENT" ]]; then
    component_filter=" AND n.component = '${COMPONENT}'"
  fi
  echo "MATCH (n) WHERE (n:ProjectFile OR n:ProjectClass OR n:ProjectFunction OR n:ProjectPackage OR n:ProjectDependency OR n:ProjectConfig OR n:ProjectLanguage OR n:DocFile OR n:DocSection OR n:DocDecision OR n:DocConstraint OR n:DocDiagram) AND n.project_id = '${PROJECT_ID}'${component_filter} DETACH DELETE n;"
}
echo ""

# ============================================================================
# Step 0b: Composite indexes for efficient scoped lookups
# ============================================================================

echo "// --- Indexes ---"
echo "CREATE INDEX project_file_idx IF NOT EXISTS FOR (n:ProjectFile) ON (n.project_id, n.component, n.path);"
echo "CREATE INDEX project_class_idx IF NOT EXISTS FOR (n:ProjectClass) ON (n.project_id, n.component, n.name);"
echo "CREATE INDEX doc_file_idx IF NOT EXISTS FOR (n:DocFile) ON (n.project_id, n.path);"
echo "CREATE INDEX project_dep_idx IF NOT EXISTS FOR (n:ProjectDependency) ON (n.project_id, n.manager);"
echo "CREATE INDEX doc_section_idx IF NOT EXISTS FOR (n:DocSection) ON (n.project_id, n.file_path);"
echo "CREATE INDEX doc_decision_idx IF NOT EXISTS FOR (n:DocDecision) ON (n.project_id, n.status);"
echo "CREATE INDEX project_pkg_idx IF NOT EXISTS FOR (n:ProjectPackage) ON (n.project_id, n.path);"
echo ""

# ============================================================================
# Step 1: Emit detected languages
# ============================================================================

echo "// --- Detected Languages ---"
while IFS= read -r lang; do
  [[ -z "$lang" ]] && continue
  echo "MERGE (:ProjectLanguage {name: '$(cypher_escape "$lang")', project_id: '${PROJECT_ID}'});"
done < <(detect_languages | sort -u)
echo ""

# ============================================================================
# Step 2: ProjectFile nodes
# ============================================================================

echo "// --- Project Files ---"

for file in "${ALL_FILES[@]}"; do
  lang="$(ext_to_lang "$file")"
  size="$(file_size "$file")"
  mod_date="$(file_date "$file")"
  echo "CREATE (:ProjectFile {path: '$(cypher_escape "$file")', language: '${lang}', size: ${size}, last_modified: '${mod_date}', project_id: '${PROJECT_ID}', component: ${COMPONENT_CYPHER}});"
done
echo ""

# ============================================================================
# Step 3: Import edges
# ============================================================================

echo "// --- Import Edges ---"
declare -A SEEN_IMPORTS=()

for file in "${ALL_FILES[@]}"; do
  lang="$(ext_to_lang "$file")"
  import_targets=""

  case "$lang" in
    typescript|javascript) import_targets="$(parse_imports_ts "$file")" ;;
    python)                import_targets="$(parse_imports_python "$file")" ;;
    kotlin|java)           import_targets="$(parse_imports_kotlin_java "$file")" ;;
    go)                    import_targets="$(parse_imports_go "$file")" ;;
    rust)                  import_targets="$(parse_imports_rust "$file")" ;;
    ruby)                  import_targets="$(parse_imports_ruby "$file")" ;;
    php)                   import_targets="$(parse_imports_php "$file")" ;;
    elixir)                import_targets="$(parse_imports_elixir "$file")" ;;
    c|cpp)                 import_targets="$(parse_imports_c_cpp "$file")" ;;
    csharp)                import_targets="$(parse_imports_csharp "$file")" ;;
  esac

  if [[ -n "$import_targets" ]]; then
    while IFS= read -r target; do
      [[ -z "$target" ]] && continue
      [[ "$target" == "$file" ]] && continue
      local_key="${file}|${target}"
      if [[ -z "${SEEN_IMPORTS[$local_key]:-}" ]]; then
        SEEN_IMPORTS["$local_key"]=1
        echo "MATCH (a:ProjectFile {path: '$(cypher_escape "$file")', project_id: '${PROJECT_ID}'}), (b:ProjectFile {path: '$(cypher_escape "$target")', project_id: '${PROJECT_ID}'}) CREATE (a)-[:IMPORTS]->(b);"
      fi
    done <<< "$import_targets"
  fi
done
echo ""

# ============================================================================
# Step 4: ProjectPackage nodes and BELONGS_TO edges
# ============================================================================

echo "// --- Packages ---"
declare -A PACKAGES=()

for file in "${ALL_FILES[@]}"; do
  dir="$(dirname "$file")"
  [[ "$dir" == "." ]] && continue
  lang="$(ext_to_lang "$file")"
  pkg_name="$dir"
  case "$lang" in
    kotlin|java|scala)
      # Strip standard JVM source roots, convert / to .
      pkg_name="$dir"
      pkg_name="${pkg_name#src/main/kotlin/}"
      pkg_name="${pkg_name#src/main/java/}"
      pkg_name="${pkg_name#src/main/scala/}"
      pkg_name="${pkg_name#app/src/main/kotlin/}"
      pkg_name="${pkg_name#app/src/main/java/}"
      pkg_name="${pkg_name#app/src/main/scala/}"
      pkg_name="${pkg_name//\//.}"
      ;;
  esac
  PACKAGES["$dir"]="$pkg_name"
done

for dir in $(printf '%s\n' "${!PACKAGES[@]}" | sort); do
  pkg_name="${PACKAGES[$dir]}"
  echo "CREATE (:ProjectPackage {name: '$(cypher_escape "$pkg_name")', path: '$(cypher_escape "$dir")', project_id: '${PROJECT_ID}', component: ${COMPONENT_CYPHER}});"
done
echo ""

echo "// --- BELONGS_TO edges ---"
for file in "${ALL_FILES[@]}"; do
  dir="$(dirname "$file")"
  [[ "$dir" == "." ]] && continue
  [[ -n "${PACKAGES[$dir]:-}" ]] || continue
  echo "MATCH (f:ProjectFile {path: '$(cypher_escape "$file")', project_id: '${PROJECT_ID}'}), (p:ProjectPackage {path: '$(cypher_escape "$dir")', project_id: '${PROJECT_ID}'}) CREATE (f)-[:BELONGS_TO]->(p);"
done
echo ""

# ============================================================================
# Step 5: Parse dependency manifests -> ProjectDependency nodes
# ============================================================================

echo "// --- Dependencies ---"
DEP_MAP="${PLUGIN_ROOT}/shared/graph/dependency-map.json"

# We collect deps into a temp file since subshell pipes lose variable state
DEP_TMPFILE="$(mktemp)"
trap "rm -f '$DEP_TMPFILE'" EXIT

emit_dep() {
  local name="$1" version="$2" scope="$3" manager="$4"
  local key="${manager}:${name}"
  # Check if already emitted (via temp file)
  if ! sgrep -qF "$key" "$DEP_TMPFILE"; then
    echo "$key" >> "$DEP_TMPFILE"
    echo "CREATE (:ProjectDependency {name: '$(cypher_escape "$name")', version: '$(cypher_escape "$version")', scope: '${scope}', manager: '${manager}', project_id: '${PROJECT_ID}', component: ${COMPONENT_CYPHER}});"
  fi
}

# --- npm (package.json) ---
if [[ -f "$PROJECT_ROOT/package.json" && -n "$FORGE_PYTHON" ]]; then
  "$FORGE_PYTHON" -c "
import json, sys
data = json.load(open('${PROJECT_ROOT}/package.json'))
for scope_key, scope_label in [('dependencies', 'runtime'), ('devDependencies', 'dev')]:
    deps = data.get(scope_key, {})
    for name in sorted(deps.keys()):
        ver = deps[name]
        print(f'{name}\t{ver}\t{scope_label}')
" 2>/dev/null | while IFS=$'\t' read -r name ver scope; do
    emit_dep "$name" "$ver" "$scope" "npm"
  done
fi

# --- Gradle (build.gradle.kts / build.gradle) ---
for gradle_file in "$PROJECT_ROOT/build.gradle.kts" "$PROJECT_ROOT/build.gradle" "$PROJECT_ROOT/app/build.gradle.kts" "$PROJECT_ROOT/app/build.gradle"; do
  [[ -f "$gradle_file" ]] || continue
  sgrep -oE '(implementation|api|testImplementation|runtimeOnly|compileOnly)[[:space:]]*\([[:space:]]*"[^"]*"' "$gradle_file" | \
    sed -E 's/^(implementation|api|testImplementation|runtimeOnly|compileOnly)[[:space:]]*\([[:space:]]*"//; s/"$//' | \
    sort -u | while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      scope="runtime"
      case "$dep" in *test*|*Test*) scope="test" ;; esac
      local_name="$(echo "$dep" | cut -d: -f1-2)"
      local_ver="$(echo "$dep" | cut -d: -f3)"
      [[ -z "$local_name" ]] && continue
      emit_dep "$local_name" "${local_ver:-unspecified}" "$scope" "maven"
    done
done

# --- pip (requirements.txt) ---
if [[ -f "$PROJECT_ROOT/requirements.txt" ]]; then
  sgrep -v '^[[:space:]]*#' "$PROJECT_ROOT/requirements.txt" | sgrep -v '^[[:space:]]*$' | \
    sed -E 's/[[:space:]]*#.*//' | sort | while IFS= read -r line; do
      name="$(echo "$line" | sed -E 's/[>=<!\[].*$//')"
      ver="$(echo "$line" | sed -E 's/^[^>=<!\[]*//')"
      [[ -z "$name" ]] && continue
      emit_dep "$name" "${ver:-any}" "runtime" "pip"
    done
fi

# --- pip (pyproject.toml) ---
if [[ -f "$PROJECT_ROOT/pyproject.toml" && -n "$FORGE_PYTHON" ]]; then
  "$FORGE_PYTHON" -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
with open('${PROJECT_ROOT}/pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
deps = data.get('project', {}).get('dependencies', [])
for dep in sorted(deps):
    parts = dep.split('>=')
    if len(parts) == 1:
        parts = dep.split('==')
    name = parts[0].strip().split('[')[0]
    ver = parts[1].strip() if len(parts) > 1 else 'any'
    print(f'{name}\t{ver}\truntime')
" 2>/dev/null | while IFS=$'\t' read -r name ver scope; do
    emit_dep "$name" "$ver" "$scope" "pip"
  done
fi

# --- Gemfile ---
if [[ -f "$PROJECT_ROOT/Gemfile" ]]; then
  sgrep -oE "gem ['\"][^'\"]+['\"]" "$PROJECT_ROOT/Gemfile" | \
    sed -E "s/gem ['\"]//; s/['\"]$//" | sort -u | while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      emit_dep "$name" "unspecified" "runtime" "gems"
    done
fi

# --- Cargo.toml ---
if [[ -f "$PROJECT_ROOT/Cargo.toml" && -n "$FORGE_PYTHON" ]]; then
  "$FORGE_PYTHON" -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
with open('${PROJECT_ROOT}/Cargo.toml', 'rb') as f:
    data = tomllib.load(f)
for section, scope in [('dependencies', 'runtime'), ('dev-dependencies', 'dev'), ('build-dependencies', 'build')]:
    deps = data.get(section, {})
    for name in sorted(deps.keys()):
        v = deps[name]
        if isinstance(v, str):
            ver = v
        elif isinstance(v, dict):
            ver = v.get('version', 'unspecified')
        else:
            ver = 'unspecified'
        print(f'{name}\t{ver}\t{scope}')
" 2>/dev/null | while IFS=$'\t' read -r name ver scope; do
    emit_dep "$name" "$ver" "$scope" "cargo"
  done
fi

# --- NuGet (.csproj) ---
while IFS= read -r csproj; do
  [[ -f "$csproj" ]] || continue
  sgrep -oE '<PackageReference Include="[^"]+" Version="[^"]+"' "$csproj" | \
    sed -E 's/<PackageReference Include="([^"]+)" Version="([^"]+)"/\1\t\2/' | \
    sort -u | while IFS=$'\t' read -r name ver; do
      [[ -z "$name" ]] && continue
      emit_dep "$name" "$ver" "runtime" "nuget"
    done
done < <(find "$PROJECT_ROOT" -name "*.csproj" -not -path "*/bin/*" -not -path "*/obj/*" 2>/dev/null | sort || true)

echo ""

# --- MAPS_TO edges (dependencies to plugin modules) ---
echo "// --- Dependency MAPS_TO edges ---"
if [[ -f "$DEP_MAP" && -s "$DEP_TMPFILE" ]]; then
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    manager="${key%%:*}"
    dep_name="${key#*:}"

    mapped_module=""
    [[ -n "$FORGE_PYTHON" ]] && mapped_module="$("$FORGE_PYTHON" -c "
import json
data = json.load(open('${DEP_MAP}'))
section = data.get('${manager}', {})
name = '''${dep_name}'''
if name in section:
    print(section[name])
elif ':' in name:
    artifact = name.split(':')[1]
    if artifact in section:
        print(section[artifact])
" 2>/dev/null || true)"

    if [[ -n "$mapped_module" ]]; then
      echo "MATCH (d:ProjectDependency {name: '$(cypher_escape "$dep_name")', project_id: '${PROJECT_ID}'}), (m) WHERE (m:LayerModule OR m:Framework OR m:TestingFramework) AND m.name = '$(cypher_escape "$mapped_module")' CREATE (d)-[:MAPS_TO]->(m);"
    fi
  done < "$DEP_TMPFILE"
fi
echo ""

# ============================================================================
# Step 6: Connect to plugin graph via forge.local.md
# ============================================================================

echo "// --- Convention Connections ---"
LOCAL_CONFIG="${PROJECT_ROOT}/.claude/forge.local.md"
if [[ -f "$LOCAL_CONFIG" && -n "$FORGE_PYTHON" ]]; then
  "$FORGE_PYTHON" -c "
import re, sys

content = open('${LOCAL_CONFIG}').read()

# Find components section
components_match = re.search(r'components:\s*\n((?:[ \t]+\S.*\n)*)', content)
if not components_match:
    sys.exit(0)

block = components_match.group(1)

for line in block.strip().split('\n'):
    line = line.strip()
    if ':' in line:
        key, _, val = line.partition(':')
        key = key.strip()
        val = val.strip().strip('\"').strip(\"'\")
        if val and val != 'null':
            print(f'{key}\t{val}')
" 2>/dev/null | while IFS=$'\t' read -r key val; do
    [[ -z "$key" || -z "$val" ]] && continue
    case "$key" in
      language)
        echo "MERGE (pc:ProjectConfig {project: '$(cypher_escape "$PROJECT_ROOT")', project_id: '${PROJECT_ID}'}) ON CREATE SET pc.language = '$(cypher_escape "$val")';"
        echo "MATCH (pc:ProjectConfig {project: '$(cypher_escape "$PROJECT_ROOT")', project_id: '${PROJECT_ID}'}), (l:Language {name: '$(cypher_escape "$val")'}) CREATE (pc)-[:USES_CONVENTION]->(l);"
        ;;
      framework)
        echo "MATCH (pc:ProjectConfig {project: '$(cypher_escape "$PROJECT_ROOT")', project_id: '${PROJECT_ID}'}), (f:Framework {name: '$(cypher_escape "$val")'}) CREATE (pc)-[:USES_CONVENTION]->(f);"
        ;;
      testing)
        echo "MATCH (pc:ProjectConfig {project: '$(cypher_escape "$PROJECT_ROOT")', project_id: '${PROJECT_ID}'}), (t:TestingFramework {name: '$(cypher_escape "$val")'}) CREATE (pc)-[:USES_CONVENTION]->(t);"
        ;;
      database|persistence|migrations|api_protocol|messaging|caching|search|storage|auth|observability|build_system|ci|container|orchestrator)
        echo "MATCH (pc:ProjectConfig {project: '$(cypher_escape "$PROJECT_ROOT")', project_id: '${PROJECT_ID}'}), (m:LayerModule {name: '$(cypher_escape "$val")'}) CREATE (pc)-[:USES_CONVENTION]->(m);"
        ;;
    esac
  done
fi
echo ""

# ============================================================================
# Step 7: Write git SHA
# ============================================================================

GIT_SHA="$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo "unknown")"
echo "$GIT_SHA" > "${GRAPH_DIR}/.last-build-sha"

echo "// --- Metadata ---"
echo "// Git SHA: ${GIT_SHA}"
echo "// Files scanned: ${#ALL_FILES[@]}"
echo "// Unresolved imports logged to: .forge/graph/.unresolved-imports.log"
