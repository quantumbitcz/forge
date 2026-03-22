#!/usr/bin/env bash
set -euo pipefail

# Unified check engine entry point.
# Detects language + module, dispatches to the appropriate layer runner(s).
# Always exits 0 — never blocks the pipeline.
#
# Modes:
#   --hook              PostToolUse hook (single file, Layer 1 only)
#   --verify            VERIFY stage (Layer 1 + Layer 2)
#   --review            REVIEW stage (Layer 1 + Layer 2 + Layer 3 stub)

trap 'exit 0' ERR

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
    .c|.h)             echo "c" ;;
    .swift)            echo "swift" ;;
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
    if [[ -f "$project_root/build.gradle.kts" ]]; then module="kotlin-spring"
    elif [[ -f "$project_root/package.json" ]] && ls "$project_root"/vite.config.* &>/dev/null; then module="react-vite"
    fi
  fi

  if [[ -n "$module" ]]; then
    mkdir -p "$project_root/.pipeline"
    echo "$module" > "$cache"
  fi
  echo "$module"
}

# --- Run Layer 1 on a single file ---
run_layer1() {
  local file="$1" project_root="${2:-}"
  local lang
  lang="$(detect_language "$file")" || true
  [[ -z "$lang" ]] && return 0
  local rules="$SCRIPT_DIR/layer-1-fast/patterns/${lang}.json"
  [[ ! -f "$rules" ]] && return 0

  local module="" override=""
  if [[ -n "$project_root" ]]; then
    module="$(detect_module "$project_root")"
    [[ -n "$module" && -f "$PLUGIN_ROOT/modules/${module}/rules-override.json" ]] && \
      override="$PLUGIN_ROOT/modules/${module}/rules-override.json"
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
    run_layer1 "$f" "$PROJECT_ROOT"
    run_layer2 "$f" "$PROJECT_ROOT"
  done
  echo "# Layer 3 (agent intelligence) not yet implemented" >&2
}

# --- Main dispatch ---
case "${1:---hook}" in
  --hook)   mode_hook ;;
  --verify) mode_verify "$@" ;;
  --review) mode_review "$@" ;;
  *)        echo "Usage: engine.sh [--hook | --verify | --review] [options]" >&2 ;;
esac

exit 0
