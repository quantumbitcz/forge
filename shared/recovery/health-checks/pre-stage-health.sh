#!/usr/bin/env bash
# pre-stage-health.sh — Checks required dependencies for a given pipeline stage.
# Usage: pre-stage-health.sh <stage_name>
# Output: "OK" if all required deps available, or "MISSING: dep1, dep2"
# Exit: always 0

set -euo pipefail

STAGE="${1:-}"
PROJECT_ROOT="${2:-$(pwd)}"

if [[ -z "$STAGE" ]]; then
  echo "MISSING: stage argument (usage: pre-stage-health.sh <stage_name>)"
  exit 0
fi

# Normalize to lowercase
STAGE="$(echo "$STAGE" | tr '[:upper:]' '[:lower:]')"

missing=()

# Check if a command exists
check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    missing+=("$1")
  fi
}

# Detect build tool from project files
detect_build_tool() {
  if [[ -f "./gradlew" ]]; then
    if [[ ! -x "./gradlew" ]]; then
      missing+=("gradlew (exists but not executable)")
    fi
  elif [[ -f "build.gradle" || -f "build.gradle.kts" ]]; then
    check_cmd "gradle"
  elif [[ -f "package.json" ]]; then
    if command -v pnpm &>/dev/null; then
      : # pnpm available
    elif command -v npm &>/dev/null; then
      : # npm available
    else
      missing+=("npm or pnpm")
    fi
  fi
}

# Detect test runner (same as build tool for most projects)
detect_test_tool() {
  detect_build_tool
}

case "$STAGE" in
  preflight)
    check_cmd "git"
    check_cmd "python3"
    # Check .claude/ is writable
    if [[ -d "$PROJECT_ROOT/.claude" ]] && [[ ! -w "$PROJECT_ROOT/.claude" ]]; then
      echo "WARN: .claude/ directory is not writable" >&2
    fi
    ;;
  explore|plan|validate|docs|learn)
    # No required external deps beyond the agent runtime
    ;;
  review)
    # Verify changed files from implementation are readable
    if [[ -d "$PROJECT_ROOT/.pipeline/worktree" ]]; then
      worktree_files="$(git -C "$PROJECT_ROOT/.pipeline/worktree" diff --name-only HEAD~1 2>/dev/null || true)"
      if [[ -n "$worktree_files" ]]; then
        while IFS= read -r f; do
          full_path="$PROJECT_ROOT/.pipeline/worktree/$f"
          if [[ ! -r "$full_path" ]]; then
            echo "WARN: Changed file not readable: $f" >&2
          fi
        done <<< "$worktree_files"
      fi
    fi
    # Check convention file exists
    conventions_file=""
    [[ -f "$PROJECT_ROOT/.claude/dev-pipeline.local.md" ]] && {
      framework="$(grep -m1 'framework:' "$PROJECT_ROOT/.claude/dev-pipeline.local.md" 2>/dev/null | sed 's/.*framework:[[:space:]]*//' || true)"
    }
    if [[ -n "${framework:-}" && "$framework" != "null" ]]; then
      conventions_path="$PROJECT_ROOT/.claude/plugins/dev-pipeline/modules/frameworks/$framework/conventions.md"
      if [[ ! -f "$conventions_path" ]]; then
        echo "WARN: Convention file not found for framework '$framework'" >&2
      fi
    fi
    ;;
  implement)
    check_cmd "git"
    detect_build_tool
    # Disk space check (min 100MB free)
    free_kb=$(df -k "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
    if [[ "$free_kb" -lt 102400 ]]; then
      echo "ERROR: Less than 100MB free disk space ($((free_kb / 1024))MB available)" >&2
    fi
    # Git state check
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
      if [[ -f "$PROJECT_ROOT/.git/MERGE_HEAD" ]]; then
        echo "ERROR: Git merge in progress — resolve before running pipeline" >&2
      fi
      if [[ -d "$PROJECT_ROOT/.git/rebase-merge" ]] || [[ -d "$PROJECT_ROOT/.git/rebase-apply" ]]; then
        echo "ERROR: Git rebase in progress — complete or abort before running pipeline" >&2
      fi
    fi
    ;;
  verify)
    detect_build_tool
    detect_test_tool
    # Disk space check (min 100MB free — same as implement)
    free_kb=$(df -k "$PROJECT_ROOT" | tail -1 | awk '{print $4}')
    if [[ "$free_kb" -lt 102400 ]]; then
      echo "ERROR: Less than 100MB free disk space ($((free_kb / 1024))MB available)" >&2
    fi
    # Framework-specific tool check (reads components: structure from local config)
    framework=""
    language=""
    [[ -f "$PROJECT_ROOT/.claude/dev-pipeline.local.md" ]] && {
      framework="$(grep -m1 'framework:' "$PROJECT_ROOT/.claude/dev-pipeline.local.md" 2>/dev/null | sed 's/.*framework:[[:space:]]*//' || true)"
      language="$(grep -m1 'language:' "$PROJECT_ROOT/.claude/dev-pipeline.local.md" 2>/dev/null | sed 's/.*language:[[:space:]]*//' || true)"
    }
    case "$framework" in
      spring|jetpack-compose|kotlin-multiplatform)
        if command -v java &>/dev/null; then
          java_ver=$(java -version 2>&1 | head -1)
          echo "INFO: Java: $java_ver" >&2
        else
          echo "WARN: Java not found — JVM builds may fail" >&2
        fi
        ;;
      react|nextjs|sveltekit|express)
        if command -v node &>/dev/null; then
          echo "INFO: Node: $(node --version)" >&2
        else
          echo "WARN: Node not found — JS/TS builds may fail" >&2
        fi
        ;;
      fastapi|django)
        if command -v python3 &>/dev/null; then
          echo "INFO: Python: $(python3 --version)" >&2
        else
          echo "WARN: Python3 not found — Python builds may fail" >&2
        fi
        ;;
      axum)
        if command -v cargo &>/dev/null; then
          echo "INFO: Cargo: $(cargo --version)" >&2
        else
          echo "WARN: Cargo not found — Rust builds may fail" >&2
        fi
        ;;
      gin|go-stdlib)
        if command -v go &>/dev/null; then
          echo "INFO: Go: $(go version)" >&2
        else
          echo "WARN: Go not found — Go builds may fail" >&2
        fi
        ;;
      swiftui|vapor)
        if command -v swift &>/dev/null; then
          echo "INFO: Swift: $(swift --version 2>&1 | head -1)" >&2
        else
          echo "WARN: Swift not found — Swift builds may fail" >&2
        fi
        ;;
      aspnet)
        if command -v dotnet &>/dev/null; then
          echo "INFO: .NET: $(dotnet --version)" >&2
        else
          echo "WARN: dotnet not found — .NET builds may fail" >&2
        fi
        ;;
    esac
    ;;
  ship)
    check_cmd "git"
    # gh is optional — check but don't fail
    if ! command -v gh &>/dev/null; then
      echo "OK (note: gh CLI not found — PR creation will be skipped)"
      exit 0
    fi
    # Check gh CLI is authenticated
    if ! gh auth status &>/dev/null 2>&1; then
      echo "WARN: gh CLI is not authenticated — PR creation will fail (run: gh auth login)" >&2
    fi
    # Check git remote is configured
    remote_url="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$remote_url" ]]; then
      echo "WARN: No git remote 'origin' configured — push and PR creation will fail" >&2
    fi
    ;;
  preview)
    # Network connectivity check
    if ! curl -s --max-time 5 https://api.github.com >/dev/null 2>&1; then
      missing+=("network connectivity")
    fi
    # Playwright is optional
    if ! command -v npx &>/dev/null; then
      echo "OK (note: npx not found — playwright checks will be skipped)"
      exit 0
    fi
    ;;
  *)
    echo "OK (unknown stage: $STAGE — no checks defined)"
    exit 0
    ;;
esac

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "OK"
else
  # Join array with comma+space
  result=""
  for dep in "${missing[@]}"; do
    if [[ -n "$result" ]]; then
      result="$result, $dep"
    else
      result="$dep"
    fi
  done
  echo "MISSING: $result"
fi

exit 0
