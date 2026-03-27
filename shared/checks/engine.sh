#!/usr/bin/env bash
set -euo pipefail

# Unified check engine entry point.
# Detects language + module, dispatches to the appropriate layer runner(s).
# Always exits 0 — never blocks the pipeline.
#
# Modes:
#   --hook              PostToolUse hook (single file, Layer 1 only)
#   --verify            VERIFY stage (Layer 1 + Layer 2)
#   --review            REVIEW stage (Layer 1 + Layer 2; Layer 3 handled by agent dispatch)
#
# Multi-component routing:
#   When .pipeline/.component-cache exists, the engine matches the file's
#   path prefix against the cache to load the correct rules-override.json
#   for the owning component's framework.  Falls back to detect_module()
#   for single-component projects (fully backward compatible).

# Track current file for error reporting
_CURRENT_FILE=""

handle_skip() {
  local skip_file=".pipeline/.check-engine-skipped"
  if [ -d ".pipeline" ]; then
    local count=0
    if [ -f "$skip_file" ]; then
      count=$(cat "$skip_file" 2>/dev/null || echo 0)
    fi
    echo $((count + 1)) > "$skip_file"
  fi
  echo "[check-engine] Hook skipped for ${_CURRENT_FILE:-unknown} (timeout/error)" >&2
  exit 0
}
trap handle_skip ERR

# Prevent double execution when both plugin hook and legacy wrapper fire
[[ -n "${_ENGINE_RUNNING:-}" ]] && exit 0
export _ENGINE_RUNNING=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-"$(cd "$SCRIPT_DIR/../.." && pwd)"}"

# --- Language detection from file extension ---
detect_language() {
  case ".${1##*.}" in
    .kt|.kts)          echo "kotlin" ;;
    .java)             echo "java" ;;
    .ts|.tsx|.js|.jsx) echo "typescript" ;;
    .py)               echo "python" ;;
    .go)               echo "go" ;;
    .rs)               echo "rust" ;;
    .cs|.csx)          echo "csharp" ;;
    .c|.h)             echo "c" ;;
    .cpp|.cc|.cxx|.hpp) echo "cpp" ;;
    .swift)            echo "swift" ;;
    .rb)               echo "ruby" ;;
    .php)              echo "php" ;;
    .dart)             echo "dart" ;;
    .ex|.exs)          echo "elixir" ;;
    .scala|.sc)        echo "scala" ;;
  esac
}

# --- Module detection (with caching) ---
detect_module() {
  local project_root="$1"
  [[ -z "$project_root" ]] && return
  local cache="$project_root/.pipeline/.module-cache"
  local cfg="$project_root/.claude/dev-pipeline.local.md"

  if [[ -f "$cache" ]] && { [[ ! -f "$cfg" ]] || [[ "$cache" -nt "$cfg" ]]; }; then
    cat "$cache"; return
  fi

  local module=""
  [[ -f "$cfg" ]] && module="$(grep -m1 '^module:' "$cfg" 2>/dev/null | sed 's/^module:[[:space:]]*//' || true)"

  if [[ -z "$module" ]]; then
    if [[ -f "$project_root/build.gradle.kts" ]] && ls "$project_root"/src/main/kotlin &>/dev/null 2>&1; then module="spring"
    elif [[ -f "$project_root/build.gradle.kts" ]] && ls "$project_root"/src/main/java &>/dev/null 2>&1; then module="spring"
    elif [[ -f "$project_root/package.json" ]] && ls "$project_root"/vite.config.* &>/dev/null 2>&1; then module="react"
    elif [[ -f "$project_root/package.json" ]] && ls "$project_root"/svelte.config.* &>/dev/null 2>&1; then module="sveltekit"
    elif [[ -f "$project_root/package.json" ]]; then module="express"
    elif [[ -f "$project_root/Cargo.toml" ]]; then module="axum"
    elif [[ -f "$project_root/go.mod" ]]; then module="go-stdlib"
    elif [[ -f "$project_root/pyproject.toml" ]]; then module="fastapi"
    elif [[ -f "$project_root/Package.swift" ]]; then module="vapor"
    elif ls "$project_root"/*.xcodeproj &>/dev/null 2>&1; then module="swiftui"
    elif [[ -f "$project_root/Makefile" ]] && ls "$project_root"/*.c &>/dev/null 2>&1; then module="embedded"
    elif ls "$project_root"/*.csproj &>/dev/null 2>&1; then module="aspnet"
    fi
  fi

  if [[ -n "$module" ]]; then
    mkdir -p "$project_root/.pipeline"
    echo "$module" > "$cache"
  fi
  echo "$module"
}

# --- Component-aware resolution ---
# resolve_component <file_path> <project_root>
# Returns: component NAME for the component that owns this file, or "" if the
# file belongs to no component (e.g. root-level infra files).
#
# Resolution order:
#   1. .pipeline/.component-cache  (path_prefix=component_name, one entry per line)
#   2. Parse components: block in dev-pipeline.local.md
#   3. Fall back to detect_module() — preserves single-component behavior
#
# Component cache format (written by the orchestrator at PREFLIGHT):
#   services/user-service=user-service
#   fe=frontend
# Each line is <relative_path_prefix>=<component_name>.  The prefix is matched
# as a leading path segment of the file's path relative to project_root.
#
# Backward compatibility: if the cache was written in the old format where the
# value is a framework name (e.g. "be=spring"), the value is returned as-is and
# treated as the component name (single-component mode — framework name == component name).
#
# Edge cases:
#   - File at project root (no subdirectory component) → first/default component
#   - File outside all component paths                 → "" (no rules applied)
#   - Single-component project (no cache, no components: block) → detect_module()
resolve_component() {
  local file_path="$1"
  local project_root="$2"

  [[ -z "$project_root" ]] && return

  local cache_file="${project_root}/.pipeline/.component-cache"
  local cfg="${project_root}/.claude/dev-pipeline.local.md"

  # --- 1. Fast path: component cache exists ---
  if [[ -f "$cache_file" ]]; then
    # Derive the path of the file relative to project_root so we can compare
    # against the stored prefix keys.
    local rel_path=""
    if [[ "$file_path" == "${project_root}"/* ]]; then
      rel_path="${file_path#"${project_root}/"}"
    else
      rel_path="$file_path"
    fi

    # Walk each cache entry; find the longest matching prefix (most specific).
    local best_prefix="" best_component=""
    while IFS='=' read -r prefix component || [[ -n "$prefix" ]]; do
      # Skip empty lines and comment lines
      [[ -z "$prefix" || "$prefix" == \#* ]] && continue
      # Match: rel_path starts with prefix followed by / or is exactly prefix
      if [[ "$rel_path" == "${prefix}" || "$rel_path" == "${prefix}/"* ]]; then
        # Prefer the longest matching prefix
        if [[ ${#prefix} -gt ${#best_prefix} ]]; then
          best_prefix="$prefix"
          best_component="$component"
        fi
      fi
    done < "$cache_file"

    if [[ -n "$best_component" ]]; then
      echo "$best_component"
      return
    fi

    # File matched no component path — root-level file or outside all components.
    # Return "" so the caller can skip framework-specific rules.
    echo ""
    return
  fi

  # --- 2. Parse components: block from dev-pipeline.local.md ---
  # Look for a multi-component config. The YAML block looks like:
  #   components:
  #     backend:
  #       path: be
  #       framework: spring
  #     frontend:
  #       path: fe
  #       framework: react
  # We do a simple line-by-line parse (no full YAML parser required):
  # collect (path, framework) pairs from indented sub-blocks under components:.
  if [[ -f "$cfg" ]]; then
    local in_components=0
    local in_component_block=0
    local current_path="" current_framework="" found_any=0
    local best_comp_prefix="" best_comp_component="" comp_indent=""

    # Derive relative path for matching
    local rel_path=""
    if [[ "$file_path" == "${project_root}"/* ]]; then
      rel_path="${file_path#"${project_root}/"}"
    else
      rel_path="$file_path"
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
      # Detect YAML frontmatter boundary (--- lines): if we hit a second ---
      # after the opening one, stop reading (end of frontmatter)
      [[ "$line" == "---" && $in_components -eq 0 ]] && continue

      # Detect top-level "components:" key (zero indentation)
      if [[ "$line" =~ ^components:[[:space:]]*$ ]]; then
        in_components=1
        continue
      fi

      # If we were in components: block and hit another top-level key, stop
      if [[ $in_components -eq 1 && "$line" =~ ^[a-zA-Z] && ! "$line" =~ ^[[:space:]] ]]; then
        in_components=0
        in_component_block=0
        continue
      fi

      [[ $in_components -eq 0 ]] && continue

      # Detect named component block (2-space indent + name + colon)
      if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z_][a-zA-Z0-9_-]*):[[:space:]]*$ ]]; then
        # Save previous component if we have both path and framework
        if [[ -n "$current_path" && -n "$current_framework" ]]; then
          found_any=1
          if [[ "$rel_path" == "${current_path}" || "$rel_path" == "${current_path}/"* ]]; then
            if [[ ${#current_path} -gt ${#best_comp_prefix} ]]; then
              best_comp_prefix="$current_path"
              best_comp_component="$current_framework"
            fi
          fi
        fi
        current_path=""
        current_framework=""
        in_component_block=1
        continue
      fi

      [[ $in_component_block -eq 0 ]] && continue

      # Parse path: and framework: within a component block (4-space indent)
      if [[ "$line" =~ ^[[:space:]]{4}path:[[:space:]]*(.+)$ ]]; then
        current_path="${BASH_REMATCH[1]}"
        # Strip inline comments and trailing whitespace
        current_path="${current_path%%#*}"
        current_path="${current_path%"${current_path##*[! ]}"}"
        continue
      fi
      if [[ "$line" =~ ^[[:space:]]{4}framework:[[:space:]]*(.+)$ ]]; then
        current_framework="${BASH_REMATCH[1]}"
        current_framework="${current_framework%%#*}"
        current_framework="${current_framework%"${current_framework##*[! ]}"}"
        continue
      fi
    done < "$cfg"

    # Handle the last component entry
    if [[ -n "$current_path" && -n "$current_framework" ]]; then
      found_any=1
      if [[ "$rel_path" == "${current_path}" || "$rel_path" == "${current_path}/"* ]]; then
        if [[ ${#current_path} -gt ${#best_comp_prefix} ]]; then
          best_comp_prefix="$current_path"
          best_comp_component="$current_framework"
        fi
      fi
    fi

    if [[ $found_any -eq 1 ]]; then
      # Multi-component config found; return best match or "" for unmatched files
      echo "$best_comp_component"
      return
    fi
  fi

  # --- 3. Single-component fallback ---
  detect_module "$project_root"
}

# --- Run Layer 1 on a single file ---
run_layer1() {
  local file="$1" project_root="${2:-}"
  local lang
  lang="$(detect_language "$file")" || true
  [[ -z "$lang" ]] && return 0
  local rules="$SCRIPT_DIR/layer-1-fast/patterns/${lang}.json"
  [[ ! -f "$rules" ]] && return 0

  local component="" override=""
  if [[ -n "$project_root" ]]; then
    component="$(resolve_component "$file" "$project_root")"
    if [[ -n "$component" ]]; then
      # 1. Try per-component cached rules (generated by orchestrator at PREFLIGHT)
      local rules_cache="${project_root}/.pipeline/.rules-cache-${component}.json"
      if [[ -f "$rules_cache" ]]; then
        override="$rules_cache"
      # 2. Fallback: framework's rules-override.json (backward compat; in
      #    single-component mode component == framework name)
      elif [[ -f "$PLUGIN_ROOT/modules/frameworks/${component}/rules-override.json" ]]; then
        override="$PLUGIN_ROOT/modules/frameworks/${component}/rules-override.json"
      fi
    fi
  fi

  if [[ -n "$override" ]]; then
    "$SCRIPT_DIR/layer-1-fast/run-patterns.sh" "$file" "$rules" "$override"
  else
    "$SCRIPT_DIR/layer-1-fast/run-patterns.sh" "$file" "$rules"
  fi
}

# --- Mode: --hook (PostToolUse, single file, Layer 1 only) ---
mode_hook() {
  local file=""
  file="$(echo "${TOOL_INPUT:-}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)" || true
  if [[ -z "$file" ]]; then
    file="$(echo "${TOOL_INPUT:-}" | grep -oE '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"file_path"\s*:\s*"//; s/"$//' || true)"
  fi

  [[ -z "$file" || ! -f "$file" ]] && return 0
  [[ "$file" == *"build/generated-sources"* ]] && return 0
  _CURRENT_FILE="$file"

  local project_root
  project_root="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || true)"
  run_layer1 "$file" "$project_root"
}

# --- Parse --project-root and --files-changed from args ---
parse_batch_args() {
  PROJECT_ROOT=""; FILES_CHANGED=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) PROJECT_ROOT="$2"; shift 2 ;;
      --files-changed) shift; while [[ $# -gt 0 && "$1" != --* ]]; do FILES_CHANGED+=("$1"); shift; done ;;
      *) shift ;;
    esac
  done
}

# --- Run Layer 2 on a single file ---
run_layer2() {
  local file="$1" project_root="${2:-}"
  local lang
  lang="$(detect_language "$file")" || true
  [[ -z "$lang" ]] && return 0
  local severity_map="$SCRIPT_DIR/layer-2-linter/config/severity-map.json"
  local runner="$SCRIPT_DIR/layer-2-linter/run-linter.sh"
  [[ ! -x "$runner" ]] && return 0
  "$runner" "$lang" "$project_root" "$file" "$severity_map"
}

# --- Mode: --verify (VERIFY stage, Layer 1 + Layer 2) ---
mode_verify() {
  shift  # consume --verify
  parse_batch_args "$@"
  for f in "${FILES_CHANGED[@]+"${FILES_CHANGED[@]}"}"; do
    [[ -f "$f" ]] || continue
    _CURRENT_FILE="$f"
    run_layer1 "$f" "$PROJECT_ROOT"
    run_layer2 "$f" "$PROJECT_ROOT"
  done
}

# --- Mode: --review (REVIEW stage, all layers) ---
mode_review() {
  shift  # consume --review
  parse_batch_args "$@"
  for f in "${FILES_CHANGED[@]+"${FILES_CHANGED[@]}"}"; do
    [[ -f "$f" ]] || continue
    _CURRENT_FILE="$f"
    run_layer1 "$f" "$PROJECT_ROOT"
    run_layer2 "$f" "$PROJECT_ROOT"
  done
  # Layer 3 (agent intelligence) is handled by dedicated agent dispatch, not shell execution.
  # - pl-140-deprecation-refresh: dispatched during PREFLIGHT by the orchestrator
  # - version-compat-reviewer: dispatched during REVIEW via quality gate batches
  # See agents/pl-140-deprecation-refresh.md and agents/version-compat-reviewer.md
}

# --- Main dispatch ---
case "${1:---hook}" in
  --hook)   mode_hook ;;
  --verify) mode_verify "$@" ;;
  --review) mode_review "$@" ;;
  *)        echo "Usage: engine.sh [--hook | --verify | --review] [options]" >&2 ;;
esac

exit 0
