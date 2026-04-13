#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# code-graph-query.sh — AST-Aware Code Search API (SQLite)
#
# Provides structured code search against .forge/code-graph.db.
# Returns JSON arrays for agent consumption.
#
# Usage:
#   ./shared/graph/code-graph-query.sh <subcommand> <args...>
#       [--project-root /path/to/project] [--db /path/to/code-graph.db]
#
# Subcommands:
#   search_class <name>                — find class/interface by name
#   search_method <name>               — find method/function globally
#   search_method_in_class <method> <class> — targeted method search
#   search_references <symbol>         — find all references to a symbol
#   search_implementations <interface> — find implementations of interface
#   search_callers <function>          — reverse call graph
#   stats                              — graph statistics summary
#
# Output: JSON array of {file, line, name, type, [signature]}
# Exit 0 always (graceful degradation).
# ============================================================================

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../platform.sh
source "${PLUGIN_ROOT}/shared/platform.sh"

# ── Defaults ─────────────────────────────────────────────────────────────────

PROJECT_ROOT=""
DB_PATH=""

# ── Parse trailing options ───────────────────────────────────────────────────

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --db)           DB_PATH="$2"; shift 2 ;;
    *)              POSITIONAL_ARGS+=("$1"); shift ;;
  esac
done

set -- "${POSITIONAL_ARGS[@]+"${POSITIONAL_ARGS[@]}"}"

# Derive project root if not provided
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(pwd)"
fi

# Derive DB path if not provided
if [[ -z "$DB_PATH" ]]; then
  DB_PATH="${PROJECT_ROOT}/.forge/code-graph.db"
fi

# ── Graceful degradation ────────────────────────────────────────────────────

if ! command -v sqlite3 &>/dev/null; then
  echo "[]"
  exit 0
fi

if [[ ! -f "$DB_PATH" ]]; then
  echo "[]"
  exit 0
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

# Escape a value for SQLite (double single quotes + escape LIKE wildcards)
sql_escape() {
  echo "$1" | sed "s/'/''/g" | sed 's/%/\\%/g' | sed 's/_/\\_/g'
}

# Run a query and format output as JSON array
# Expects columns: file_path, start_line, name, kind, signature
query_to_json() {
  local sql="$1"
  local result
  result="$(sqlite3 -json "$DB_PATH" "$sql" 2>/dev/null)" || result="[]"

  # sqlite3 -json outputs JSON directly on newer versions
  if [[ "$result" == "["* ]]; then
    echo "$result"
    return
  fi

  # Fallback: use separator mode and build JSON manually
  result="$(sqlite3 -separator '|' "$DB_PATH" "$sql" 2>/dev/null)" || {
    echo "[]"
    return
  }

  if [[ -z "$result" ]]; then
    echo "[]"
    return
  fi

  # Build JSON array
  local json="["
  local first=true
  while IFS='|' read -r file_path start_line name kind signature; do
    [[ -z "$file_path" ]] && continue
    if [[ "$first" != "true" ]]; then
      json="${json},"
    fi
    first=false
    # Escape JSON strings
    file_path="${file_path//\\/\\\\}"
    file_path="${file_path//\"/\\\"}"
    name="${name//\\/\\\\}"
    name="${name//\"/\\\"}"
    kind="${kind//\\/\\\\}"
    kind="${kind//\"/\\\"}"
    signature="${signature//\\/\\\\}"
    signature="${signature//\"/\\\"}"
    json="${json}{\"file\":\"${file_path}\",\"line\":${start_line:-0},\"name\":\"${name}\",\"type\":\"${kind}\""
    if [[ -n "$signature" ]]; then
      json="${json},\"signature\":\"${signature}\""
    fi
    json="${json}}"
  done <<< "$result"
  json="${json}]"
  echo "$json"
}

# ── Subcommands ──────────────────────────────────────────────────────────────

cmd_search_class() {
  local name="$1"
  local name_esc
  name_esc="$(sql_escape "$name")"

  query_to_json "
    SELECT file_path, start_line, name, kind, signature
    FROM nodes
    WHERE kind IN ('Class', 'Interface')
      AND name LIKE '%${name_esc}%' ESCAPE '\\'
    ORDER BY
      CASE WHEN name = '${name_esc}' THEN 0 ELSE 1 END,
      name, file_path
    LIMIT 50;
  "
}

cmd_search_method() {
  local name="$1"
  local name_esc
  name_esc="$(sql_escape "$name")"

  query_to_json "
    SELECT file_path, start_line, name, kind, signature
    FROM nodes
    WHERE kind IN ('Function', 'Method', 'Test')
      AND name LIKE '%${name_esc}%' ESCAPE '\\'
    ORDER BY
      CASE WHEN name = '${name_esc}' THEN 0 ELSE 1 END,
      name, file_path
    LIMIT 50;
  "
}

cmd_search_method_in_class() {
  local method="$1"
  local class="$2"
  local method_esc class_esc
  method_esc="$(sql_escape "$method")"
  class_esc="$(sql_escape "$class")"

  query_to_json "
    SELECT m.file_path, m.start_line, m.name, m.kind, m.signature
    FROM nodes m
    JOIN edges e ON e.target_id = m.id AND e.edge_type = 'CONTAINS'
    JOIN nodes c ON c.id = e.source_id
      AND c.kind IN ('Class', 'Interface')
      AND c.name = '${class_esc}'
    WHERE m.kind IN ('Function', 'Method', 'Test')
      AND m.name LIKE '%${method_esc}%' ESCAPE '\\'
    ORDER BY m.name, m.file_path
    LIMIT 50;
  "
}

cmd_search_references() {
  local symbol="$1"
  local symbol_esc
  symbol_esc="$(sql_escape "$symbol")"

  query_to_json "
    SELECT DISTINCT n2.file_path, n2.start_line, n2.name, n2.kind, n2.signature
    FROM nodes n1
    JOIN edges e ON e.target_id = n1.id
      AND e.edge_type IN ('CALLS', 'REFERENCES', 'IMPORTS', 'INSTANTIATES', 'INHERITS', 'IMPLEMENTS')
    JOIN nodes n2 ON n2.id = e.source_id
    WHERE n1.name = '${symbol_esc}'
    UNION
    SELECT DISTINCT n2.file_path, n2.start_line, n2.name, n2.kind, n2.signature
    FROM nodes n1
    JOIN edges e ON e.source_id = n1.id
      AND e.edge_type IN ('CONTAINS')
    JOIN nodes n2 ON n2.id = e.target_id
    WHERE n1.name = '${symbol_esc}'
    ORDER BY 1, 2
    LIMIT 100;
  "
}

cmd_search_implementations() {
  local interface="$1"
  local iface_esc
  iface_esc="$(sql_escape "$interface")"

  query_to_json "
    SELECT n2.file_path, n2.start_line, n2.name, n2.kind, n2.signature
    FROM nodes n1
    JOIN edges e ON e.target_id = n1.id AND e.edge_type = 'IMPLEMENTS'
    JOIN nodes n2 ON n2.id = e.source_id
    WHERE n1.name = '${iface_esc}'
      AND n1.kind = 'Interface'
    ORDER BY n2.name, n2.file_path
    LIMIT 50;
  "
}

cmd_search_callers() {
  local function="$1"
  local func_esc
  func_esc="$(sql_escape "$function")"

  query_to_json "
    SELECT DISTINCT n2.file_path, n2.start_line, n2.name, n2.kind, n2.signature
    FROM nodes n1
    JOIN edges e ON e.target_id = n1.id AND e.edge_type = 'CALLS'
    JOIN nodes n2 ON n2.id = e.source_id
    WHERE n1.name = '${func_esc}'
    ORDER BY n2.file_path, n2.start_line
    LIMIT 100;
  "
}

cmd_stats() {
  local total_nodes total_edges total_files
  total_nodes="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM nodes;" 2>/dev/null || echo "0")"
  total_edges="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM edges;" 2>/dev/null || echo "0")"
  total_files="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM file_hashes;" 2>/dev/null || echo "0")"

  local last_build version project_id
  last_build="$(sqlite3 "$DB_PATH" "SELECT value FROM schema_meta WHERE key='last_build_timestamp';" 2>/dev/null || echo "unknown")"
  version="$(sqlite3 "$DB_PATH" "SELECT value FROM schema_meta WHERE key='version';" 2>/dev/null || echo "unknown")"
  project_id="$(sqlite3 "$DB_PATH" "SELECT value FROM schema_meta WHERE key='project_id';" 2>/dev/null || echo "unknown")"

  # Node breakdown by kind
  local node_breakdown
  node_breakdown="$(sqlite3 -separator '|' "$DB_PATH" "
    SELECT kind, COUNT(*) FROM nodes GROUP BY kind ORDER BY COUNT(*) DESC;
  " 2>/dev/null || echo "")"

  # Edge breakdown by type
  local edge_breakdown
  edge_breakdown="$(sqlite3 -separator '|' "$DB_PATH" "
    SELECT edge_type, COUNT(*) FROM edges GROUP BY edge_type ORDER BY COUNT(*) DESC;
  " 2>/dev/null || echo "")"

  # Build JSON
  local json="{\"version\":\"${version}\",\"project_id\":\"${project_id}\",\"last_build\":\"${last_build}\","
  json="${json}\"total_nodes\":${total_nodes},\"total_edges\":${total_edges},\"total_files\":${total_files},"

  # Node kinds
  json="${json}\"node_kinds\":{"
  local first=true
  while IFS='|' read -r kind count; do
    [[ -z "$kind" ]] && continue
    [[ "$first" != "true" ]] && json="${json},"
    first=false
    json="${json}\"${kind}\":${count}"
  done <<< "$node_breakdown"
  json="${json}},"

  # Edge types
  json="${json}\"edge_types\":{"
  first=true
  while IFS='|' read -r etype count; do
    [[ -z "$etype" ]] && continue
    [[ "$first" != "true" ]] && json="${json},"
    first=false
    json="${json}\"${etype}\":${count}"
  done <<< "$edge_breakdown"
  json="${json}}"

  json="${json}}"
  echo "$json"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

SUBCOMMAND="${1:-}"
shift 2>/dev/null || true

case "$SUBCOMMAND" in
  search_class)
    [[ $# -lt 1 ]] && { echo "Usage: code-graph-query.sh search_class <name>" >&2; echo "[]"; exit 0; }
    cmd_search_class "$1"
    ;;
  search_method)
    [[ $# -lt 1 ]] && { echo "Usage: code-graph-query.sh search_method <name>" >&2; echo "[]"; exit 0; }
    cmd_search_method "$1"
    ;;
  search_method_in_class)
    [[ $# -lt 2 ]] && { echo "Usage: code-graph-query.sh search_method_in_class <method> <class>" >&2; echo "[]"; exit 0; }
    cmd_search_method_in_class "$1" "$2"
    ;;
  search_references)
    [[ $# -lt 1 ]] && { echo "Usage: code-graph-query.sh search_references <symbol>" >&2; echo "[]"; exit 0; }
    cmd_search_references "$1"
    ;;
  search_implementations)
    [[ $# -lt 1 ]] && { echo "Usage: code-graph-query.sh search_implementations <interface>" >&2; echo "[]"; exit 0; }
    cmd_search_implementations "$1"
    ;;
  search_callers)
    [[ $# -lt 1 ]] && { echo "Usage: code-graph-query.sh search_callers <function>" >&2; echo "[]"; exit 0; }
    cmd_search_callers "$1"
    ;;
  stats)
    cmd_stats
    ;;
  "")
    echo "Usage: code-graph-query.sh <subcommand> [args...] [--project-root /path] [--db /path/to/db]" >&2
    echo "" >&2
    echo "Subcommands:" >&2
    echo "  search_class <name>                — find class/interface by name" >&2
    echo "  search_method <name>               — find method/function globally" >&2
    echo "  search_method_in_class <method> <class> — targeted method search" >&2
    echo "  search_references <symbol>         — find all references to a symbol" >&2
    echo "  search_implementations <interface> — find implementations of interface" >&2
    echo "  search_callers <function>          — reverse call graph" >&2
    echo "  stats                              — graph statistics summary" >&2
    echo "[]"
    exit 0
    ;;
  *)
    echo "Unknown subcommand: $SUBCOMMAND" >&2
    echo "[]"
    exit 0
    ;;
esac
