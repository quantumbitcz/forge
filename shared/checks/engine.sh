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
#   When .forge/.component-cache exists, the engine matches the file's
#   path prefix against the cache to load the correct rules-override.json
#   for the owning component's framework.  Falls back to detect_module()
#   for single-component projects (fully backward compatible).
#
# Requires bash 4.0+ for BASH_REMATCH (regex capture groups).
# macOS ships bash 3.2 — install bash 4+ via: brew install bash
if (( BASH_VERSINFO[0] < 4 )); then
  echo "[check-engine] WARNING: Bash 4.0+ required. Current: ${BASH_VERSION}. Skipping checks." >&2
  # Increment skip counter so VERIFY stage surfaces that checks were skipped.
  # Cannot reuse handle_skip() — it's defined after this guard and may use
  # bash 4+ constructs (flock subshell). Simple non-atomic increment is fine
  # since this code path only runs once per session (not concurrent).
  _skip_file=".forge/.check-engine-skipped"
  _log_dir="${FORGE_DIR:-.forge}"
  if [ -d ".forge" ]; then
    _count=0; [ -f "$_skip_file" ] && _count=$(cat "$_skip_file" 2>/dev/null || echo 0)
    echo $((_count + 1)) > "$_skip_file" 2>/dev/null || true
  fi
  # Log failure inline (handle_failure not yet defined; see comment above)
  if [ -d "$_log_dir" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u) | engine.sh | skip:bash_version_${BASH_VERSION} | n/a" \
      >> "${_log_dir}/.hook-failures.log" 2>/dev/null || true
  fi
  exit 0
fi

# Portable glob-match helper: returns 0 if any file matches the pattern.
# Replaces compgen -G which is a bash builtin not available on all platforms.
# Canonical version lives in shared/platform.sh — kept inline here to avoid
# sourcing platform.sh on every Edit/Write hook invocation (performance).
_glob_exists() {
  local pattern="$1"
  local f
  for f in $pattern; do
    [ -e "$f" ] && return 0
  done
  return 1
}

# Track current file for error reporting
_CURRENT_FILE=""

# Log hook failures to .forge/.hook-failures.log for observability.
# Called before silent exits so operators can audit skipped checks.
handle_failure() {
  local reason="$1"
  local file="${2:-unknown}"
  local log_dir="${FORGE_DIR:-.forge}"
  if [[ -d "$log_dir" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u) | engine.sh | ${reason} | ${file}" \
      >> "${log_dir}/.hook-failures.log"
  fi
}

# shellcheck disable=SC2329  # invoked indirectly via hook timeout handler
handle_skip() {
  local skip_file=".forge/.check-engine-skipped"
  if [ -d ".forge" ]; then
    # Atomic increment: use flock if available, else mkdir-based lock
    if command -v flock &>/dev/null; then
      (
        flock -w 2 9 || exit 0  # Lock timeout: skip increment (best-effort counter)
        local count=0
        [ -f "$skip_file" ] && count=$(cat "$skip_file" 2>/dev/null || echo 0)
        echo $((count + 1)) > "$skip_file"
      ) 9>"${skip_file}.lock"
      # Lock file intentionally not removed — avoids TOCTOU race with concurrent flock callers.
      # The file is in .forge/ (gitignored) so it is harmless to leave behind.
    else
      local lock_dir="${skip_file}.lockdir"
      if mkdir "$lock_dir" 2>/dev/null; then
        local count=0
        [ -f "$skip_file" ] && count=$(cat "$skip_file" 2>/dev/null || echo 0)
        echo $((count + 1)) > "$skip_file"
        rmdir "$lock_dir" 2>/dev/null
      fi
      # If lock fails, skip the increment — best-effort counter
    fi
  fi
  handle_failure "skip:timeout_or_error" "${_CURRENT_FILE:-unknown}"
  echo "[check-engine] Hook skipped for ${_CURRENT_FILE:-unknown} (timeout/error)" >&2
  exit 0
}
trap handle_skip ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-"$(cd "$SCRIPT_DIR/../.." && pwd)"}"

# --- Language detection from file extension ---
detect_language() {
  # Dockerfile detection by filename (no standard extension)
  local basename="${1##*/}"
  case "$basename" in
    Dockerfile|Dockerfile.*|*.dockerfile) echo "dockerfile"; return ;;
  esac
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
    .yml|.yaml)        echo "yaml" ;;
  esac
}

# --- Module detection (with caching) ---
detect_module() {
  local project_root="$1"
  [[ -z "$project_root" ]] && return
  local cache="$project_root/.forge/.module-cache"
  local cfg="$project_root/.claude/forge.local.md"

  if [[ -f "$cache" && -s "$cache" ]] && { [[ ! -f "$cfg" ]] || [[ "$cache" -nt "$cfg" ]]; }; then
    cat "$cache"; return
  fi

  local module=""
  if [[ -f "$cfg" ]]; then
    # Try components.framework first (current format), fall back to legacy module: field
    module="$(grep -m1 '^[[:space:]]*framework:' "$cfg" 2>/dev/null | sed 's/^[[:space:]]*framework:[[:space:]]*//' || true)"
    [[ -z "$module" ]] && module="$(grep -m1 '^module:' "$cfg" 2>/dev/null | sed 's/^module:[[:space:]]*//' || true)"
  fi

  if [[ -z "$module" ]]; then
    if [[ -f "$project_root/build.gradle.kts" ]] && grep -qE 'org\.jetbrains\.compose|androidx\.compose' "$project_root/build.gradle.kts" 2>/dev/null; then module="jetpack-compose"
    elif [[ -f "$project_root/build.gradle.kts" ]] && grep -qE 'org\.jetbrains\.kotlin\.multiplatform|kotlin\("multiplatform"\)' "$project_root/build.gradle.kts" 2>/dev/null; then module="kotlin-multiplatform"
    elif [[ -f "$project_root/build.gradle.kts" ]] && grep -qE 'spring-boot|org\.springframework' "$project_root/build.gradle.kts" 2>/dev/null; then module="spring"
    elif [[ -f "$project_root/build.gradle" ]] && grep -qE 'spring-boot|org\.springframework' "$project_root/build.gradle" 2>/dev/null; then module="spring"
    elif [[ -f "$project_root/angular.json" ]]; then module="angular"
    elif [[ -f "$project_root/package.json" ]] && _glob_exists "$project_root"/next.config.*; then module="nextjs"
    elif [[ -f "$project_root/package.json" ]] && _glob_exists "$project_root"/svelte.config.*; then module="sveltekit"
    elif [[ -f "$project_root/package.json" ]] && [[ -f "$project_root/nest-cli.json" ]]; then module="nestjs"
    elif [[ -f "$project_root/package.json" ]] && grep -q '"vue"' "$project_root/package.json" 2>/dev/null; then module="vue"
    elif [[ -f "$project_root/package.json" ]] && grep -q '"svelte"' "$project_root/package.json" 2>/dev/null; then module="svelte"
    elif [[ -f "$project_root/package.json" ]] && _glob_exists "$project_root"/vite.config.*; then
      # Vue and Svelte already handled above; remaining Vite projects default to react
      module="react"
    # Bare package.json defaults to express for linter module selection (intentional —
    # detect-project-type.sh requires explicit evidence, but engine.sh needs a module for rules)
    elif [[ -f "$project_root/package.json" ]]; then module="express"
    # Rust/Python: require framework evidence to avoid false positives. Projects without
    # a recognized framework get no module — only language-level Layer 1 rules apply.
    elif [[ -f "$project_root/Cargo.toml" ]] && grep -q 'axum' "$project_root/Cargo.toml" 2>/dev/null; then module="axum"
    elif [[ -f "$project_root/go.mod" ]] && grep -q 'gin-gonic/gin' "$project_root/go.mod" 2>/dev/null; then module="gin"
    elif [[ -f "$project_root/go.mod" ]]; then module="go-stdlib"
    elif [[ -f "$project_root/manage.py" ]]; then module="django"
    elif [[ -f "$project_root/pyproject.toml" ]] && grep -q 'fastapi' "$project_root/pyproject.toml" 2>/dev/null; then module="fastapi"
    elif [[ -f "$project_root/Package.swift" ]]; then module="vapor"
    elif _glob_exists "$project_root"/*.xcodeproj; then module="swiftui"
    elif [[ -f "$project_root/Makefile" ]] && _glob_exists "$project_root"/*.c; then module="embedded"
    elif _glob_exists "$project_root"/*.csproj; then module="aspnet"
    elif _glob_exists "$project_root"/*.yaml && grep -ql 'apiVersion:' "$project_root"/*.yaml 2>/dev/null; then module="k8s"
    fi
  fi

  if [[ -n "$module" ]]; then
    mkdir -p "$project_root/.forge"
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
#   1. .forge/.component-cache  (path_prefix=component_name, one entry per line)
#   2. Parse components: block in forge.local.md
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

  local cache_file="${project_root}/.forge/.component-cache"
  local cfg="${project_root}/.claude/forge.local.md"

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

  # --- 2. Parse components: block from forge.local.md ---
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
  #
  # Indentation: expects 2-space for component names and 4-space for path/framework
  # fields. If non-standard indentation is detected, a WARNING is emitted to stderr
  # and the parser falls back to detect_module() (single-component mode).
  # All forge-generated templates use 2-space indent.
  if [[ -f "$cfg" ]]; then
    local in_components=0
    local in_component_block=0
    local current_path="" current_framework="" found_any=0
    local best_comp_prefix="" best_comp_component=""
    local indent_warned=0

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

      # --- Indentation validation ---
      # Detect non-2-space indentation inside components: block.
      # Only check lines that look like component names (indented word + colon),
      # and only before we've entered a valid component block.
      if [[ $indent_warned -eq 0 && $in_component_block -eq 0 ]]; then
        if [[ "$line" =~ ^$'\t' ]]; then
          echo "[check-engine] WARNING: Tab indentation detected in components: block of forge.local.md. Expected 2-space indentation. Multi-component detection will not work — falling back to single-component mode. Fix: convert tabs to 2-space indentation or run /forge-init to regenerate config." >&2
          indent_warned=1
          break  # Stop parsing — will fall through to detect_module()
        elif [[ "$line" =~ ^[[:space:]]{3,}[a-zA-Z_] ]]; then
          # 3+ leading spaces: this is NOT the expected 2-space indent for component names.
          # (2-space lines are caught by the component regex below, so reaching here means non-standard.)
          echo "[check-engine] WARNING: Non-standard indentation detected in components: block of forge.local.md (expected 2-space, found different). Multi-component detection will not work — falling back to single-component mode. Fix: use 2-space indentation or run /forge-init to regenerate config." >&2
          indent_warned=1
          break  # Stop parsing — will fall through to detect_module()
        fi
      fi

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
      local rules_cache="${project_root}/.forge/.rules-cache-${component}.json"
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
  local py_cmd="python3"
  command -v python3 &>/dev/null || py_cmd="python"
  file="$(echo "${TOOL_INPUT:-}" | "$py_cmd" -c "import json,sys; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)" || true
  if [[ -z "$file" ]]; then
    file="$(echo "${TOOL_INPUT:-}" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)"
  fi

  [[ -z "$file" || ! -f "$file" ]] && return 0
  [[ "$file" == *"build/generated-sources"* ]] && return 0

  # Deferred batch mode: queue file instead of processing immediately
  if [[ "${FORGE_BATCH_HOOK:-}" == "1" && -n "${FORGE_HOOK_QUEUE:-}" ]]; then
    echo "$file" >> "$FORGE_HOOK_QUEUE"
    return 0
  fi

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
  # Files are processed sequentially; grouping by language is available in --flush-queue mode.
  # In verify/review, sequential per-file processing ensures correct component resolution.
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
  # Files are processed sequentially; grouping by language is available in --flush-queue mode.
  # In verify/review, sequential per-file processing ensures correct component resolution.
  for f in "${FILES_CHANGED[@]+"${FILES_CHANGED[@]}"}"; do
    [[ -f "$f" ]] || continue
    _CURRENT_FILE="$f"
    run_layer1 "$f" "$PROJECT_ROOT"
    run_layer2 "$f" "$PROJECT_ROOT"
  done
  # Layer 3 (agent intelligence) is handled by dedicated agent dispatch, not shell execution.
  # - fg-140-deprecation-refresh: dispatched during PREFLIGHT by the orchestrator
  # - fg-417-version-compat-reviewer: dispatched during REVIEW via quality gate batches
  # See agents/fg-140-deprecation-refresh.md and agents/fg-417-version-compat-reviewer.md
}

# --- Mode: --flush-queue (process deferred hook queue) ---
mode_flush_queue() {
  shift  # consume --flush-queue
  local queue_file="" project_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="$2"; shift 2 ;;
      --queue-file) queue_file="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -z "$queue_file" || ! -f "$queue_file" ]] && return 0
  [[ ! -s "$queue_file" ]] && return 0

  # Read unique files from queue
  local -A seen_files=()
  local files=()
  while IFS= read -r f; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    [[ -n "${seen_files[$f]+x}" ]] && continue
    seen_files[$f]=1
    files+=("$f")
  done < "$queue_file"

  # Group files by language for efficient batch processing
  local -A file_groups=()
  for f in "${files[@]}"; do
    local lang
    lang="$(detect_language "$f")" || true
    [[ -z "$lang" ]] && continue
    file_groups[$lang]+="$f"$'\n'
  done

  # Process each language group — Layer 1 only, matching hook mode behavior.
  # Layer 2 (linter) runs during --verify/--review stages, not deferred hooks.
  for lang in "${!file_groups[@]}"; do
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      _CURRENT_FILE="$f"
      run_layer1 "$f" "$project_root"
    done <<< "${file_groups[$lang]}"
  done

  # Clear the queue
  : > "$queue_file"
}

# --- Acquire instance lock (prevents double execution) ---
# Placed after function definitions so test wrappers that extract functions
# via awk (stopping at "Acquire instance lock") are not affected by the lock.
# Uses atomic file lock instead of env var (which has a TOCTOU race between
# concurrent hook invocations in the same shell session).
# The lock dir must exist; if it doesn't, skip locking (no forge project context).
_LOCK_DIR="${FORGE_DIR:-.forge}"
if [[ -d "$_LOCK_DIR" ]]; then
  LOCK_FILE="${_LOCK_DIR}/.engine.lock"
  if command -v flock &>/dev/null; then
    exec 200>"$LOCK_FILE"
    flock -n 200 || exit 0  # Another instance running, skip silently
  else
    # macOS fallback: mkdir-based lock (atomic on POSIX)
    if ! mkdir "$LOCK_FILE.d" 2>/dev/null; then
      exit 0  # Another instance running
    fi
    trap 'rmdir "$LOCK_FILE.d" 2>/dev/null' EXIT
  fi
fi

# --- Main dispatch ---
case "${1:---hook}" in
  --hook)        mode_hook ;;
  --verify)      mode_verify "$@" ;;
  --review)      mode_review "$@" ;;
  --flush-queue) mode_flush_queue "$@" ;;
  *)             echo "Usage: engine.sh [--hook | --verify | --review | --flush-queue] [options]" >&2 ;;
esac

exit 0
