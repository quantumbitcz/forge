#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# build-code-graph.sh — AST-Based Code Graph Builder (Tree-sitter + SQLite)
#
# Zero-dependency alternative to the Neo4j knowledge graph. Parses source
# files via tree-sitter CLI, extracts nodes and edges, stores in SQLite.
#
# Usage:
#   ./shared/graph/build-code-graph.sh --project-root /path/to/project \
#       [--project-id org/repo] [--component api] [--incremental]
#
# Output: .forge/code-graph.db (SQLite database)
# Exit 0 on success or graceful degradation (tree-sitter not found).
# ============================================================================

# Support --source-only for unit testing
if [[ "${1:-}" == "--source-only" ]]; then
  _SOURCE_ONLY=true
  shift
else
  _SOURCE_ONLY=false
fi

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../platform.sh
source "${PLUGIN_ROOT}/shared/platform.sh"

require_bash4 "build-code-graph.sh" || exit 1

SCHEMA_FILE="${PLUGIN_ROOT}/shared/graph/code-graph-schema.sql"

# ── Defaults ─────────────────────────────────────────────────────────────────

PROJECT_ROOT=""
PROJECT_ID=""
COMPONENT=""
INCREMENTAL=false

# Config defaults (overridden by forge-config.md if present)
CODE_GRAPH_ENABLED=true
MAX_FILE_SIZE_KB=500
PARSE_TIMEOUT_SECONDS=300
PER_FILE_TIMEOUT_MS=5000
EXCLUDE_PATTERNS=("node_modules" ".git" "vendor" "build" "dist" ".gradle" ".idea" "__pycache__" ".mypy_cache" "target" ".forge")

# ── Argument parsing & config (skipped in --source-only mode) ────────────────

if [[ "$_SOURCE_ONLY" != "true" ]]; then

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)  PROJECT_ROOT="$2"; shift 2 ;;
    --project-id)    PROJECT_ID="$2"; shift 2 ;;
    --component)     COMPONENT="$2"; shift 2 ;;
    --incremental)   INCREMENTAL=true; shift ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: build-code-graph.sh --project-root /path [--project-id id] [--component name] [--incremental]" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo "Error: --project-root is required" >&2
  exit 1
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
fi

# ── Read config from forge-config.md if present ─────────────────────────────

CONFIG_FILE="${PROJECT_ROOT}/.claude/forge-admin config.md"
if [[ -f "$CONFIG_FILE" && -n "$FORGE_PYTHON" ]]; then
  eval "$("$FORGE_PYTHON" -c "
import re, sys

content = open(sys.argv[1]).read()

# Find code_graph section
m = re.search(r'code_graph:\s*\n((?:[ \t]+\S.*\n)*)', content)
if not m:
    sys.exit(0)

block = m.group(1)
for line in block.strip().split('\n'):
    line = line.strip()
    if ':' not in line:
        continue
    key, _, val = line.partition(':')
    key = key.strip()
    val = val.strip().strip('\"').strip(\"'\")
    if key == 'enabled' and val in ('false', 'False', 'no'):
        print('CODE_GRAPH_ENABLED=false')
    elif key == 'max_file_size_kb' and val.isdigit():
        print(f'MAX_FILE_SIZE_KB={val}')
    elif key == 'parse_timeout_seconds' and val.isdigit():
        print(f'PARSE_TIMEOUT_SECONDS={val}')
    elif key == 'per_file_timeout_ms' and val.isdigit():
        print(f'PER_FILE_TIMEOUT_MS={val}')
" "$CONFIG_FILE" 2>/dev/null || true)"
fi

if [[ "$CODE_GRAPH_ENABLED" != "true" ]]; then
  echo "[code-graph] Code graph is disabled via config." >&2
  exit 0
fi

# ── Check prerequisites ─────────────────────────────────────────────────────

if ! command -v sqlite3 &>/dev/null; then
  echo "[code-graph] WARNING: sqlite3 not found. Code graph disabled." >&2
  exit 0
fi

if ! command -v tree-sitter &>/dev/null; then
  echo "[code-graph] INFO: tree-sitter CLI not found. Code graph disabled." >&2
  echo "[code-graph] Install: $(suggest_install tree-sitter)" >&2
  exit 0
fi

# ── Ensure .forge directory ──────────────────────────────────────────────────

FORGE_DIR="${PROJECT_ROOT}/.forge"
mkdir -p "$FORGE_DIR"
DB_PATH="${FORGE_DIR}/code-graph.db"

fi # end _SOURCE_ONLY guard

# ── Language extension mapping ───────────────────────────────────────────────

# Maps file extensions to tree-sitter language names
ext_to_ts_lang() {
  case "$1" in
    *.kt|*.kts)          echo "kotlin" ;;
    *.java)              echo "java" ;;
    *.ts)                echo "typescript" ;;
    *.tsx)               echo "tsx" ;;
    *.js)                echo "javascript" ;;
    *.jsx)               echo "javascript" ;;
    *.py)                echo "python" ;;
    *.go)                echo "go" ;;
    *.rs)                echo "rust" ;;
    *.swift)             echo "swift" ;;
    *.c|*.h)             echo "c" ;;
    *.cs)                echo "c_sharp" ;;
    *.rb)                echo "ruby" ;;
    *.php)               echo "php" ;;
    *.dart)              echo "dart" ;;
    *.ex|*.exs)          echo "elixir" ;;
    *.scala)             echo "scala" ;;
    *.cpp|*.cc|*.cxx|*.hpp) echo "cpp" ;;
    *)                   echo "" ;;
  esac
}

# Maps tree-sitter language to forge language name
ts_lang_to_forge_lang() {
  case "$1" in
    kotlin)      echo "kotlin" ;;
    java)        echo "java" ;;
    typescript)  echo "typescript" ;;
    tsx)         echo "typescript" ;;
    javascript)  echo "javascript" ;;
    python)      echo "python" ;;
    go)          echo "go" ;;
    rust)        echo "rust" ;;
    swift)       echo "swift" ;;
    c)           echo "c" ;;
    c_sharp)     echo "csharp" ;;
    ruby)        echo "ruby" ;;
    php)         echo "php" ;;
    dart)        echo "dart" ;;
    elixir)      echo "elixir" ;;
    scala)       echo "scala" ;;
    cpp)         echo "cpp" ;;
    *)           echo "unknown" ;;
  esac
}

# Source extensions for git ls-files filtering
SOURCE_EXTS='\.kt$|\.kts$|\.java$|\.ts$|\.tsx$|\.js$|\.jsx$|\.py$|\.go$|\.rs$|\.swift$|\.c$|\.h$|\.cs$|\.rb$|\.php$|\.dart$|\.ex$|\.exs$|\.scala$|\.cpp$|\.cc$|\.cxx$|\.hpp$'

# ── Build exclude arguments ─────────────────────────────────────────────────

build_exclude_grep() {
  local pattern=""
  for exc in "${EXCLUDE_PATTERNS[@]}"; do
    if [[ -n "$pattern" ]]; then
      pattern="${pattern}|"
    fi
    pattern="${pattern}(^|/)${exc}(/|$)"
  done
  echo "$pattern"
}

EXCLUDE_REGEX="$(build_exclude_grep)"

# ── Detect test paths ───────────────────────────────────────────────────────

is_test_file() {
  local file="$1"
  case "$file" in
    *test/*|*tests/*|*spec/*|*specs/*|*__tests__/*|*Test.*|*_test.*|*_spec.*|*.test.*|*.spec.*|*Tests.*|*Spec.*)
      return 0
      ;;
  esac
  return 1
}

# ── SHA256 helper ────────────────────────────────────────────────────────────

file_sha256() {
  if command -v shasum &>/dev/null; then
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v sha256sum &>/dev/null; then
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  else
    # Fallback via python
    [[ -n "$FORGE_PYTHON" ]] && "$FORGE_PYTHON" -c "
import hashlib, sys
with open(sys.argv[1], 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())
" "$1" 2>/dev/null
  fi
}

# ── Collect source files ────────────────────────────────────────────────────

collect_source_files() {
  if [[ -d "$PROJECT_ROOT/.git" ]]; then
    cd "$PROJECT_ROOT" && git ls-files 2>/dev/null | grep -E "$SOURCE_EXTS" | grep -vE "$EXCLUDE_REGEX" || true
  else
    # Non-git fallback: find
    cd "$PROJECT_ROOT" && find . -type f | sed 's|^\./||' | grep -E "$SOURCE_EXTS" | grep -vE "$EXCLUDE_REGEX" || true
  fi
}

# ── Initialize or verify database ───────────────────────────────────────────

init_db() {
  local db="$1"

  # Check if DB exists and has valid schema
  if [[ -f "$db" ]]; then
    local version
    version="$(sqlite3 "$db" "SELECT value FROM schema_meta WHERE key='version';" 2>/dev/null || echo "")"
    if [[ "$version" == "1.0.0" ]]; then
      return 0  # DB is valid
    fi
    # Corrupted or incompatible — remove and rebuild
    echo "[code-graph] WARNING: Invalid or corrupted database. Rebuilding." >&2
    rm -f "$db"
  fi

  # Create fresh database
  sqlite3 "$db" < "$SCHEMA_FILE"
  sqlite3 "$db" "INSERT OR REPLACE INTO schema_meta VALUES ('version', '1.0.0');"
  sqlite3 "$db" "INSERT OR REPLACE INTO schema_meta VALUES ('project_id', '$(echo "$PROJECT_ID" | sed "s/'/''/g")');"
  sqlite3 "$db" "PRAGMA journal_mode=WAL;"
  sqlite3 "$db" "PRAGMA foreign_keys=ON;"
}

# ── Parse a single file with tree-sitter ─────────────────────────────────────

# Outputs lines of the form:
#   NODE|kind|name|start_line|end_line|start_col|end_col|signature|visibility
#   EDGE|edge_type|source_name|source_kind|target_name|target_kind
#
# Uses tree-sitter parse to get S-expression AST, then extracts via Python.

parse_file_with_treesitter() {
  local file="$1"
  local ts_lang="$2"
  local abs_path="${PROJECT_ROOT}/${file}"

  [[ -f "$abs_path" ]] || return 0

  # Check file size
  local file_size_kb
  file_size_kb=$(( $(wc -c < "$abs_path" | tr -d ' ') / 1024 ))
  if (( file_size_kb > MAX_FILE_SIZE_KB )); then
    echo "[code-graph] INFO: Skipping $file (${file_size_kb}KB > ${MAX_FILE_SIZE_KB}KB limit)" >&2
    return 0
  fi

  # Try to parse with tree-sitter; timeout per file
  local timeout_seconds=$(( PER_FILE_TIMEOUT_MS / 1000 ))
  [[ $timeout_seconds -lt 1 ]] && timeout_seconds=1

  local ast_output
  ast_output="$(portable_timeout "$timeout_seconds" tree-sitter parse "$abs_path" 2>/dev/null)" || {
    echo "[code-graph] INFO: tree-sitter parse failed or timed out for $file" >&2
    return 0
  }

  [[ -z "$ast_output" ]] && return 0

  # Use Python to extract structured node/edge information from S-expression AST
  if [[ -z "$FORGE_PYTHON" ]]; then
    echo "[code-graph] WARNING: Python not available. Cannot extract AST nodes." >&2
    return 0
  fi

  "$FORGE_PYTHON" << 'PYEOF' - "$file" "$ts_lang" "$abs_path" "$ast_output"
import sys
import re
import os

file_path = sys.argv[1]
ts_lang = sys.argv[2]
abs_path = sys.argv[3]
ast_text = sys.argv[4]

# Read source file for line-level analysis
try:
    with open(abs_path, 'r', errors='replace') as f:
        lines = f.readlines()
except Exception:
    lines = []

# ── Language-specific AST node type mappings ──────────────────────────────

# Maps tree-sitter node types to our graph node kinds
NODE_TYPE_MAP = {
    # Class-like
    'class_declaration': 'Class',
    'class_definition': 'Class',
    'class_specifier': 'Class',
    'class': 'Class',
    'object_declaration': 'Class',
    'struct_item': 'Class',
    'struct_specifier': 'Class',
    'data_class_declaration': 'Class',

    # Interface-like
    'interface_declaration': 'Interface',
    'trait_item': 'Interface',
    'trait_definition': 'Interface',
    'protocol_declaration': 'Interface',

    # Function-like
    'function_declaration': 'Function',
    'function_definition': 'Function',
    'function_item': 'Function',
    'arrow_function': 'Function',
    'func_literal': 'Function',
    'function_signature': 'Function',

    # Method-like
    'method_declaration': 'Method',
    'method_definition': 'Method',
    'method': 'Method',
    'method_signature': 'Method',

    # Module-like
    'module_declaration': 'Module',
    'package_declaration': 'Module',
    'namespace_declaration': 'Module',
    'module': 'Module',
    'defmodule': 'Module',

    # Import-like
    'import_statement': 'Import',
    'import_declaration': 'Import',
    'use_declaration': 'Import',
    'using_directive': 'Import',

    # Export-like
    'export_statement': 'Export',
    'export_declaration': 'Export',

    # Type-like
    'type_alias_declaration': 'Type',
    'type_item': 'Type',
    'type_declaration': 'Type',
    'type_definition': 'Type',

    # Enum-like
    'enum_declaration': 'Enum',
    'enum_item': 'Enum',
    'enum_definition': 'Enum',
    'enum_specifier': 'Enum',

    # Constant-like
    'const_declaration': 'Constant',
    'const_item': 'Constant',

    # Decorator/annotation
    'annotation': 'Decorator',
    'decorator': 'Decorator',
    'attribute_item': 'Decorator',
    'decorated_definition': 'Decorator',

    # Variable
    'variable_declaration': 'Variable',
    'variable_declarator': 'Variable',
    'let_declaration': 'Variable',
    'val_declaration': 'Variable',
    'var_declaration': 'Variable',
}

# Patterns in the S-expression AST
# tree-sitter parse output looks like: (node_type [start_row, start_col] - [end_row, end_col] ...)
node_pattern = re.compile(
    r'\((\w+)\s+\[(\d+),\s*(\d+)\]\s*-\s*\[(\d+),\s*(\d+)\]'
)

nodes_found = []
# Track parent-child for CONTAINS edges
node_stack = []  # Stack of (kind, name, depth)

# Parse the S-expression to find nodes
depth = 0
for line in ast_text.split('\n'):
    stripped = line.lstrip()
    # Calculate depth from indentation
    current_depth = len(line) - len(stripped)

    for match in node_pattern.finditer(line):
        node_type = match.group(1)
        start_row = int(match.group(2))
        start_col = int(match.group(3))
        end_row = int(match.group(4))
        end_col = int(match.group(5))

        kind = NODE_TYPE_MAP.get(node_type)
        if kind is None:
            continue

        # Extract name from the source line
        name = ''
        if start_row < len(lines):
            source_line = lines[start_row].rstrip()
            # Try to extract an identifier name
            # Look for common patterns: class Foo, def foo, function foo, etc.
            name_patterns = [
                r'(?:class|interface|struct|enum|trait|object|module|protocol)\s+(\w+)',
                r'(?:fun|func|function|def|defp|defmodule|fn)\s+(\w+)',
                r'(?:const|let|var|val)\s+(\w+)',
                r'(?:type)\s+(\w+)',
                r'(\w+)\s*[=:({]',
            ]
            for pat in name_patterns:
                m = re.search(pat, source_line)
                if m:
                    name = m.group(1)
                    break
            if not name:
                # Fallback: use first identifier-like word after the keyword
                tokens = re.findall(r'\b\w+\b', source_line)
                for tok in tokens:
                    if tok not in ('class', 'interface', 'struct', 'enum', 'fun',
                                   'func', 'function', 'def', 'defp', 'defmodule',
                                   'public', 'private', 'protected', 'internal',
                                   'static', 'abstract', 'final', 'open', 'sealed',
                                   'override', 'suspend', 'async', 'export',
                                   'import', 'const', 'let', 'var', 'val', 'type',
                                   'fn', 'pub', 'mod', 'use', 'impl', 'trait',
                                   'module', 'namespace', 'package', 'object',
                                   'data', 'inline', 'external', 'actual', 'expect',
                                   'companion', 'annotation', 'return', 'void',
                                   'int', 'string', 'bool', 'float', 'double'):
                        name = tok
                        break

        if not name:
            continue

        # Detect visibility
        visibility = 'public'  # default
        if start_row < len(lines):
            src = lines[start_row]
            if 'private' in src:
                visibility = 'private'
            elif 'protected' in src:
                visibility = 'protected'
            elif 'internal' in src:
                visibility = 'internal'
            # Rust/Elixir: no pub = private
            if ts_lang in ('rust',) and 'pub' not in src:
                visibility = 'private'
            if ts_lang in ('elixir',) and 'defp' in src:
                visibility = 'private'

        # Build signature for functions/methods
        signature = ''
        if kind in ('Function', 'Method') and start_row < len(lines):
            sig_line = lines[start_row].strip()
            # Truncate at opening brace or first 120 chars
            brace_pos = sig_line.find('{')
            if brace_pos > 0:
                sig_line = sig_line[:brace_pos].rstrip()
            signature = sig_line[:120]

        nodes_found.append({
            'kind': kind,
            'name': name,
            'start_line': start_row + 1,  # 1-indexed
            'end_line': end_row + 1,
            'start_col': start_col,
            'end_col': end_col,
            'signature': signature,
            'visibility': visibility,
            'depth': current_depth,
        })

# Detect test functions by name/annotation patterns
test_patterns = re.compile(
    r'(^test_|_test$|Test$|^Test|@Test|@test|#\[test\]|#\[cfg\(test\)\]|'
    r'describe\(|it\(|test\(|@pytest\.mark|def test|func Test)',
    re.IGNORECASE
)

for node in nodes_found:
    is_test = 0
    if node['kind'] in ('Function', 'Method'):
        if test_patterns.search(node['name']):
            is_test = 1
        # Check if file is in test directory
        elif any(p in file_path for p in ('test/', 'tests/', 'spec/', 'specs/', '__tests__/')):
            is_test = 1
    kind = 'Test' if is_test and node['kind'] in ('Function', 'Method') else node['kind']

    # Escape single quotes for SQL
    name_esc = node['name'].replace("'", "''")
    sig_esc = node['signature'].replace("'", "''")
    vis = node['visibility']

    print(f"NODE|{kind}|{name_esc}|{node['start_line']}|{node['end_line']}|"
          f"{node['start_col']}|{node['end_col']}|{sig_esc}|{vis}")

# Emit CONTAINS edges based on depth/nesting
# Classes/Modules contain their Methods/Functions
for i, outer in enumerate(nodes_found):
    if outer['kind'] not in ('Class', 'Interface', 'Module', 'Enum'):
        continue
    for inner in nodes_found[i+1:]:
        if inner['depth'] <= outer['depth']:
            break
        if inner['kind'] in ('Function', 'Method', 'Variable', 'Constant', 'Type', 'Enum'):
            o_name = outer['name'].replace("'", "''")
            o_kind = outer['kind']
            i_name = inner['name'].replace("'", "''")
            i_kind = 'Test' if inner.get('_is_test') else inner['kind']
            print(f"EDGE|CONTAINS|{o_name}|{o_kind}|{i_name}|{i_kind}")

# Emit File CONTAINS top-level nodes
for node in nodes_found:
    if node['depth'] <= 2:  # Top-level nodes (low nesting depth)
        n_name = node['name'].replace("'", "''")
        n_kind = node['kind']
        print(f"EDGE|CONTAINS_FILE|{n_name}|{n_kind}||")

# Detect inheritance/implementation from source lines
for node in nodes_found:
    if node['kind'] not in ('Class', 'Interface'):
        continue
    if node['start_line'] - 1 < len(lines):
        src = lines[node['start_line'] - 1]
        # extends/implements patterns
        extends_match = re.findall(r'(?:extends|:)\s+(\w+)', src)
        implements_match = re.findall(r'(?:implements|:)\s+.*?(\w+)', src)
        for parent in extends_match:
            if parent != node['name'] and parent[0].isupper():
                p_esc = parent.replace("'", "''")
                n_esc = node['name'].replace("'", "''")
                print(f"EDGE|INHERITS|{n_esc}|{node['kind']}|{p_esc}|Class")
        for iface in implements_match:
            if iface != node['name'] and iface[0].isupper() and iface not in extends_match:
                i_esc = iface.replace("'", "''")
                n_esc = node['name'].replace("'", "''")
                print(f"EDGE|IMPLEMENTS|{n_esc}|{node['kind']}|{i_esc}|Interface")

# Detect function calls (simple heuristic: identifier followed by '(')
all_func_names = {n['name'] for n in nodes_found if n['kind'] in ('Function', 'Method')}
call_pattern = re.compile(r'\b(\w+)\s*\(')
for node in nodes_found:
    if node['kind'] not in ('Function', 'Method'):
        continue
    for line_num in range(node['start_line'] - 1, min(node['end_line'], len(lines))):
        for m in call_pattern.finditer(lines[line_num]):
            callee = m.group(1)
            if callee in all_func_names and callee != node['name']:
                caller_esc = node['name'].replace("'", "''")
                callee_esc = callee.replace("'", "''")
                print(f"EDGE|CALLS|{caller_esc}|{node['kind']}|{callee_esc}|Function")

PYEOF
}

# ── Process a single file: parse, hash, insert ──────────────────────────────

process_file() {
  local file="$1"
  local db="$2"
  local ts_lang forge_lang is_test_flag

  ts_lang="$(ext_to_ts_lang "$file")"
  [[ -z "$ts_lang" ]] && return 0

  forge_lang="$(ts_lang_to_forge_lang "$ts_lang")"

  # Compute hash
  local abs_path="${PROJECT_ROOT}/${file}"
  local content_hash
  content_hash="$(file_sha256 "$abs_path")"
  [[ -z "$content_hash" ]] && return 0

  # Check if file is unchanged (incremental mode)
  if [[ "$INCREMENTAL" == "true" ]]; then
    local stored_hash
    stored_hash="$(sqlite3 "$db" "SELECT content_hash FROM file_hashes WHERE file_path='$(echo "$file" | sed "s/'/''/g")';" 2>/dev/null || echo "")"
    if [[ "$stored_hash" == "$content_hash" ]]; then
      return 0  # File unchanged
    fi
    # File changed — remove old data
    remove_file_from_db "$file" "$db"
  fi

  is_test_flag=0
  is_test_file "$file" && is_test_flag=1

  local component_sql="NULL"
  if [[ -n "$COMPONENT" ]]; then
    component_sql="'$(echo "$COMPONENT" | sed "s/'/''/g")'"
  fi

  local file_esc
  file_esc="$(echo "$file" | sed "s/'/''/g")"

  # Create File node
  sqlite3 "$db" "INSERT OR IGNORE INTO nodes (kind, name, file_path, start_line, end_line, language, component, is_test)
    VALUES ('File', '${file_esc}', '${file_esc}', 1, 0, '${forge_lang}', ${component_sql}, ${is_test_flag});"

  # Parse with tree-sitter and extract nodes/edges
  local parse_start parse_end parse_duration_ms
  parse_start="$(date +%s%N 2>/dev/null || date +%s)"

  local parse_output
  parse_output="$(parse_file_with_treesitter "$file" "$ts_lang" 2>/dev/null)" || true

  parse_end="$(date +%s%N 2>/dev/null || date +%s)"
  # Calculate duration (handle systems without nanosecond support)
  if [[ ${#parse_start} -gt 10 && ${#parse_end} -gt 10 ]]; then
    parse_duration_ms=$(( (parse_end - parse_start) / 1000000 ))
  else
    parse_duration_ms=$(( (parse_end - parse_start) * 1000 ))
  fi

  local node_count=0
  local edge_count=0

  if [[ -n "$parse_output" ]]; then
    # Build SQL statements in batch
    local sql_batch=""

    while IFS='|' read -r record_type f1 f2 f3 f4 f5 f6 f7 f8; do
      case "$record_type" in
        NODE)
          local kind="$f1" name="$f2" start_line="$f3" end_line="$f4"
          local start_col="$f5" end_col="$f6" signature="$f7" visibility="$f8"
          sql_batch="${sql_batch}INSERT OR IGNORE INTO nodes (kind, name, file_path, start_line, end_line, start_col, end_col, language, component, signature, visibility, is_test)
            VALUES ('${kind}', '${name}', '${file_esc}', ${start_line}, ${end_line}, ${start_col}, ${end_col}, '${forge_lang}', ${component_sql}, '${signature}', '${visibility}', ${is_test_flag});
"
          ((node_count++)) || true
          ;;
        EDGE)
          local edge_type="$f1" src_name="$f2" src_kind="$f3" tgt_name="$f4" tgt_kind="$f5"

          if [[ "$edge_type" == "CONTAINS_FILE" ]]; then
            # File CONTAINS node
            sql_batch="${sql_batch}INSERT OR IGNORE INTO edges (edge_type, source_id, target_id)
              SELECT 'CONTAINS', f.id, n.id
              FROM nodes f, nodes n
              WHERE f.kind='File' AND f.file_path='${file_esc}'
                AND n.name='${src_name}' AND n.file_path='${file_esc}' AND n.kind='${src_kind}'
              LIMIT 1;
"
          else
            # Named edge between nodes in same file
            sql_batch="${sql_batch}INSERT OR IGNORE INTO edges (edge_type, source_id, target_id)
              SELECT '${edge_type}', s.id, t.id
              FROM nodes s, nodes t
              WHERE s.name='${src_name}' AND s.file_path='${file_esc}'
                AND t.name='${tgt_name}' AND t.file_path='${file_esc}'
              LIMIT 1;
"
          fi
          ((edge_count++)) || true
          ;;
      esac
    done <<< "$parse_output"

    # Execute batch
    if [[ -n "$sql_batch" ]]; then
      sqlite3 "$db" "BEGIN TRANSACTION;
${sql_batch}COMMIT;" 2>/dev/null || {
        echo "[code-graph] WARNING: SQL batch failed for $file" >&2
      }
    fi
  fi

  # Update file hash
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"
  sqlite3 "$db" "INSERT OR REPLACE INTO file_hashes (file_path, content_hash, last_parsed_at, parse_duration_ms, node_count, edge_count)
    VALUES ('${file_esc}', '${content_hash}', '${now}', ${parse_duration_ms}, ${node_count}, ${edge_count});"
}

# ── Remove a file's data from the database ───────────────────────────────────

remove_file_from_db() {
  local file="$1"
  local db="$2"
  local file_esc
  file_esc="$(echo "$file" | sed "s/'/''/g")"

  sqlite3 "$db" "
    DELETE FROM edges WHERE source_id IN (SELECT id FROM nodes WHERE file_path='${file_esc}');
    DELETE FROM edges WHERE target_id IN (SELECT id FROM nodes WHERE file_path='${file_esc}');
    DELETE FROM communities WHERE node_id IN (SELECT id FROM nodes WHERE file_path='${file_esc}');
    DELETE FROM nodes WHERE file_path='${file_esc}';
    DELETE FROM file_hashes WHERE file_path='${file_esc}';
  " 2>/dev/null || true
}

# ── Build cross-file edges ───────────────────────────────────────────────────

build_cross_file_edges() {
  local db="$1"
  local boundary_map="${FORGE_DIR}/module-boundary-map.json"

  echo "[code-graph] Building cross-file edges..." >&2

  if [[ -f "$boundary_map" && -n "${FORGE_PYTHON:-}" ]]; then
    echo "[code-graph] Using module-boundary-aware resolution." >&2
    build_cross_file_edges_with_boundaries "$db" "$boundary_map"
  else
    echo "[code-graph] Using heuristic resolution (no boundary map)." >&2
    build_cross_file_edges_heuristic "$db"
  fi

  # CALLS edges across files (unchanged from original)
  sqlite3 "$db" "
    INSERT OR IGNORE INTO edges (edge_type, source_id, target_id)
    SELECT 'CALLS', caller.id, callee.id
    FROM nodes caller
    JOIN edges e ON e.edge_type='CALLS' AND e.source_id = caller.id
    JOIN nodes intra_target ON intra_target.id = e.target_id AND intra_target.file_path = caller.file_path
    JOIN nodes callee ON callee.name = intra_target.name
      AND callee.kind IN ('Function', 'Method')
      AND callee.file_path != caller.file_path
    WHERE caller.kind IN ('Function', 'Method');
  " 2>/dev/null || true

  # TESTS edges (unchanged from original)
  sqlite3 "$db" "
    INSERT OR IGNORE INTO edges (edge_type, source_id, target_id)
    SELECT 'TESTS', test_file.id, prod_file.id
    FROM nodes test_file
    JOIN nodes prod_file ON prod_file.kind='File' AND prod_file.is_test=0
    WHERE test_file.kind='File' AND test_file.is_test=1
      AND (
        REPLACE(REPLACE(REPLACE(REPLACE(test_file.name, 'Test', ''), '_test', ''), '.test', ''), '.spec', '')
        LIKE '%' || REPLACE(REPLACE(prod_file.name, '.kt', ''), '.java', '') || '%'
        OR REPLACE(REPLACE(REPLACE(test_file.name, '_test.', '.'), '.test.', '.'), '.spec.', '.')
          = prod_file.name
      )
      AND test_file.file_path != prod_file.file_path;
  " 2>/dev/null || true
}

build_cross_file_edges_heuristic() {
  local db="$1"

  # Original IMPORTS heuristic (preserved as fallback)
  sqlite3 "$db" "
    INSERT OR IGNORE INTO edges (edge_type, source_id, target_id, properties)
    SELECT 'IMPORTS', src_file.id, tgt_file.id, '{\"confidence\":\"heuristic\"}'
    FROM nodes imp
    JOIN nodes src_file ON src_file.kind='File' AND src_file.file_path = imp.file_path
    JOIN nodes tgt_file ON tgt_file.kind='File'
      AND (tgt_file.name LIKE '%' || REPLACE(REPLACE(imp.name, '.', '/'), '::', '/') || '%'
           OR imp.name LIKE '%' || REPLACE(tgt_file.file_path, '/', '.') || '%')
    WHERE imp.kind='Import'
      AND src_file.file_path != tgt_file.file_path;
  " 2>/dev/null || true
}

build_cross_file_edges_with_boundaries() {
  local db="$1" boundary_map="$2"

  "${FORGE_PYTHON:-python3}" << 'PYEOF' - "$db" "$boundary_map"
import json, sys, sqlite3, os, re

db_path = sys.argv[1]
boundary_map_path = sys.argv[2]

with open(boundary_map_path) as f:
    bmap = json.load(f)

modules = bmap.get("modules", [])

# Build file_path -> module_name index
file_to_module = {}
module_by_name = {}
for mod in modules:
    module_by_name[mod["name"]] = mod
    for src_dir in mod.get("source_dirs", []) + mod.get("test_dirs", []):
        file_to_module[src_dir] = mod["name"]

def resolve_file_to_module(file_path):
    for src_dir, mod_name in file_to_module.items():
        if file_path.startswith(src_dir + '/') or file_path == src_dir:
            return mod_name
    return None

# Build module dependency graph
module_deps = {m["name"]: set(m.get("depends_on", [])) for m in modules}

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
c = conn.cursor()

# Get all Import nodes
imports = c.execute("SELECT id, name, file_path, language FROM nodes WHERE kind='Import'").fetchall()

# Get all File nodes indexed by file_path
file_nodes = {}
for row in c.execute("SELECT id, name, file_path FROM nodes WHERE kind='File'"):
    file_nodes[row["file_path"]] = row["id"]

# Also build a reverse index: basename -> [file_paths]
basename_to_paths = {}
for fp in file_nodes:
    bn = os.path.basename(fp)
    basename_to_paths.setdefault(bn, []).append(fp)

def generate_candidates(import_name, language):
    """Generate candidate file paths from an import name."""
    candidates = []
    lang = (language or "").lower()

    if lang in ("java", "kotlin", "scala"):
        # com.example.core.Service -> com/example/core/Service.{java,kt,scala}
        path_base = import_name.replace(".", "/")
        for ext in [".java", ".kt", ".scala"]:
            candidates.append(path_base + ext)
        # Also try just the class name
        parts = import_name.rsplit(".", 1)
        if len(parts) == 2:
            class_name = parts[1]
            for ext in [".java", ".kt", ".scala"]:
                candidates.append(class_name + ext)

    elif lang == "python":
        # app.services.user -> app/services/user.py, app/services/user/__init__.py
        path_base = import_name.replace(".", "/")
        candidates.append(path_base + ".py")
        candidates.append(path_base + "/__init__.py")

    elif lang == "go":
        # github.com/example/project/pkg/auth -> pkg/auth/
        parts = import_name.split("/")
        if len(parts) >= 3:
            # Strip the domain (first 3 parts typically)
            local_parts = parts[3:] if len(parts) > 3 else parts[-1:]
            local_path = "/".join(local_parts)
            candidates.append(local_path + "/")

    elif lang == "rust":
        # crate::models::user -> src/models/user.rs, src/models/user/mod.rs
        cleaned = import_name.replace("crate::", "").replace("::", "/")
        candidates.append("src/" + cleaned + ".rs")
        candidates.append("src/" + cleaned + "/mod.rs")

    elif lang in ("typescript", "javascript", "tsx"):
        # @scope/pkg -> workspace match; ./services/User -> relative
        cleaned = import_name.lstrip("./").lstrip("@")
        for ext in [".ts", ".tsx", ".js", ".jsx"]:
            candidates.append(cleaned + ext)
        candidates.append(cleaned + "/index.ts")
        candidates.append(cleaned + "/index.js")

    elif lang in ("c_sharp", "csharp"):
        # Project.Models -> Models/
        parts = import_name.split(".")
        for i in range(len(parts)):
            sub = "/".join(parts[i:])
            candidates.append(sub + ".cs")

    elif lang == "ruby":
        candidates.append(import_name.replace("::", "/") + ".rb")

    elif lang in ("c", "cpp"):
        candidates.append(import_name)

    else:
        # Generic: try dot-to-slash
        path_base = import_name.replace(".", "/")
        candidates.append(path_base)

    return candidates

edges_to_insert = []

for imp in imports:
    imp_id = imp["id"]
    imp_name = imp["name"]
    imp_file = imp["file_path"]
    imp_lang = imp["language"]

    source_file_id = file_nodes.get(imp_file)
    if not source_file_id:
        continue

    source_module = resolve_file_to_module(imp_file)
    candidates = generate_candidates(imp_name, imp_lang)

    resolved = False

    # Step 1: same-module resolution
    if source_module and source_module in module_by_name:
        mod = module_by_name[source_module]
        for src_dir in mod.get("source_dirs", []):
            for cand in candidates:
                full_path = src_dir + "/" + cand if not cand.startswith(src_dir) else cand
                if full_path in file_nodes:
                    edges_to_insert.append((source_file_id, file_nodes[full_path], "resolved"))
                    resolved = True
                    break
            if resolved:
                break

    # Step 2: cross-module (declared dependency)
    if not resolved and source_module:
        for dep_mod_name in module_deps.get(source_module, []):
            if dep_mod_name in module_by_name:
                dep_mod = module_by_name[dep_mod_name]
                for src_dir in dep_mod.get("source_dirs", []):
                    for cand in candidates:
                        full_path = src_dir + "/" + cand if not cand.startswith(src_dir) else cand
                        if full_path in file_nodes:
                            edges_to_insert.append((source_file_id, file_nodes[full_path], "resolved"))
                            resolved = True
                            break
                    if resolved:
                        break
            if resolved:
                break

    # Step 3: any module (undeclared dependency)
    if not resolved:
        for mod in modules:
            if mod["name"] == source_module:
                continue
            for src_dir in mod.get("source_dirs", []):
                for cand in candidates:
                    full_path = src_dir + "/" + cand if not cand.startswith(src_dir) else cand
                    if full_path in file_nodes:
                        edges_to_insert.append((source_file_id, file_nodes[full_path], "module-inferred"))
                        resolved = True
                        break
                if resolved:
                    break
            if resolved:
                break

    # Step 4: heuristic fallback (basename matching)
    if not resolved:
        # Try matching by the last segment of the import name
        last_segment = imp_name.rsplit(".", 1)[-1].rsplit("::", 1)[-1]
        for ext in [".java", ".kt", ".py", ".go", ".rs", ".ts", ".tsx", ".js", ".cs", ".rb", ".scala", ".swift", ".cpp", ".c", ".h", ".php", ".dart", ".ex", ".exs"]:
            bn = last_segment + ext
            if bn in basename_to_paths:
                for fp in basename_to_paths[bn]:
                    if fp != imp_file:
                        edges_to_insert.append((source_file_id, file_nodes[fp], "heuristic"))
                        resolved = True
                        break
            if resolved:
                break

# Batch insert all edges
for src_id, tgt_id, confidence in edges_to_insert:
    try:
        c.execute(
            "INSERT OR IGNORE INTO edges (edge_type, source_id, target_id, properties) VALUES ('IMPORTS', ?, ?, ?)",
            (src_id, tgt_id, json.dumps({"confidence": confidence}))
        )
    except Exception:
        pass

conn.commit()
conn.close()

sys.stderr.write(f"[code-graph] Module-aware resolution: {len(edges_to_insert)} IMPORTS edges created.\n")
PYEOF
}

# ── Metrics emission ────────────────────────────────────────────────────────

emit_build_graph_metrics() {
  local db="$1"
  local state_file="${FORGE_DIR}/state.json"

  [[ -f "$state_file" ]] || return 0
  [[ -n "${FORGE_PYTHON:-}" ]] || return 0

  local total resolved inferred heuristic

  total="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS';" 2>/dev/null || echo 0)"
  resolved="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS' AND json_extract(properties, '$.confidence')='resolved';" 2>/dev/null || echo 0)"
  inferred="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS' AND json_extract(properties, '$.confidence')='module-inferred';" 2>/dev/null || echo 0)"
  heuristic="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS' AND json_extract(properties, '$.confidence')='heuristic';" 2>/dev/null || echo 0)"

  local total_imports resolved_imports unresolved
  total_imports="$(sqlite3 "$db" "SELECT COUNT(*) FROM nodes WHERE kind='Import';" 2>/dev/null || echo 0)"
  resolved_imports="$(sqlite3 "$db" "SELECT COUNT(DISTINCT n.id) FROM nodes n WHERE n.kind='Import' AND EXISTS (SELECT 1 FROM edges e JOIN nodes src ON src.kind='File' AND src.file_path = n.file_path AND e.source_id = src.id WHERE e.edge_type='IMPORTS');" 2>/dev/null || echo 0)"
  unresolved=$(( total_imports - resolved_imports ))
  [[ $unresolved -lt 0 ]] && unresolved=0

  local accuracy="0.0"
  if [[ $total -gt 0 ]]; then
    accuracy="$("${FORGE_PYTHON:-python3}" -c "print(round(($resolved + $inferred) / $total, 3))" 2>/dev/null || echo "0.0")"
  fi

  "${FORGE_PYTHON:-python3}" -c "
import json, sys
state_path = sys.argv[1]
try:
    with open(state_path) as f:
        state = json.load(f)
except (json.JSONDecodeError, IOError):
    state = {}
state['build_graph'] = {
    'edges_total': int(sys.argv[2]),
    'edges_resolved': int(sys.argv[3]),
    'edges_module_inferred': int(sys.argv[4]),
    'edges_heuristic': int(sys.argv[5]),
    'edges_unresolved': int(sys.argv[6]),
    'resolution_accuracy': float(sys.argv[7])
}
with open(state_path, 'w') as f:
    json.dump(state, f, indent=2)
" "$state_file" "$total" "$resolved" "$inferred" "$heuristic" "$unresolved" "$accuracy" \
    2>/dev/null || true

  echo "[code-graph] Metrics: total=$total resolved=$resolved inferred=$inferred heuristic=$heuristic unresolved=$unresolved accuracy=$accuracy" >&2
}

# ── Main build logic ────────────────────────────────────────────────────────

if [[ "${_SOURCE_ONLY:-false}" == "true" ]]; then
  # When sourced for testing, skip main execution
  return 0 2>/dev/null || true
fi

echo "[code-graph] Building code graph for ${PROJECT_ROOT}..." >&2
echo "[code-graph] Mode: $(if [[ "$INCREMENTAL" == "true" ]]; then echo "incremental"; else echo "full"; fi)" >&2

init_db "$DB_PATH"

# Enable WAL mode and foreign keys for this session
sqlite3 "$DB_PATH" "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;"

# Collect files
declare -a SOURCE_FILES=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  SOURCE_FILES+=("$f")
done < <(collect_source_files)

echo "[code-graph] Found ${#SOURCE_FILES[@]} source files to process." >&2

if [[ ${#SOURCE_FILES[@]} -eq 0 ]]; then
  echo "[code-graph] No source files found. Skipping." >&2
  exit 0
fi

# Track timing
BUILD_START="$(date +%s)"
FILES_PROCESSED=0
FILES_SKIPPED=0

for file in "${SOURCE_FILES[@]}"; do
  # Check total timeout
  local_now="$(date +%s)"
  elapsed=$(( local_now - BUILD_START ))
  if (( elapsed >= PARSE_TIMEOUT_SECONDS )); then
    echo "[code-graph] WARNING: Parse timeout reached (${PARSE_TIMEOUT_SECONDS}s). Stopping with partial graph." >&2
    break
  fi

  process_file "$file" "$DB_PATH" 2>/dev/null && ((FILES_PROCESSED++)) || ((FILES_SKIPPED++)) || true
done

# Build cross-file relationships
build_cross_file_edges "$DB_PATH"

# Emit build graph quality metrics to state.json
emit_build_graph_metrics "$DB_PATH"

# Handle deleted files in incremental mode
if [[ "$INCREMENTAL" == "true" ]]; then
  # Find files in DB that no longer exist on disk
  deleted_count=0
  while IFS= read -r old_file; do
    [[ -z "$old_file" ]] && continue
    if [[ ! -f "${PROJECT_ROOT}/${old_file}" ]]; then
      remove_file_from_db "$old_file" "$DB_PATH"
      ((deleted_count++)) || true
    fi
  done < <(sqlite3 "$DB_PATH" "SELECT file_path FROM file_hashes;" 2>/dev/null)
  if [[ ${deleted_count:-0} -gt 0 ]]; then
    echo "[code-graph] Removed ${deleted_count} deleted files from graph." >&2
  fi
fi

# Update metadata
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"
GIT_SHA="$(cd "$PROJECT_ROOT" && git rev-parse HEAD 2>/dev/null || echo "unknown")"
sqlite3 "$DB_PATH" "
  INSERT OR REPLACE INTO schema_meta VALUES ('last_build_sha', '${GIT_SHA}');
  INSERT OR REPLACE INTO schema_meta VALUES ('last_build_timestamp', '${NOW}');
  INSERT OR REPLACE INTO schema_meta VALUES ('project_id', '$(echo "$PROJECT_ID" | sed "s/'/''/g")');
"

# Summary
TOTAL_NODES="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "?")"
TOTAL_EDGES="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM edges;" 2>/dev/null || echo "?")"
BUILD_END="$(date +%s)"
BUILD_DURATION=$(( BUILD_END - BUILD_START ))

echo "[code-graph] Build complete in ${BUILD_DURATION}s." >&2
echo "[code-graph] Files processed: ${FILES_PROCESSED}, skipped: ${FILES_SKIPPED}" >&2
echo "[code-graph] Total nodes: ${TOTAL_NODES}, edges: ${TOTAL_EDGES}" >&2
echo "[code-graph] Database: ${DB_PATH}" >&2
