#!/usr/bin/env bash
# Cross-platform detection helpers for dev-pipeline scripts.
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/platform.sh"

# ── OS Detection ─────────────────────────────────────────────────────────────

# Returns: darwin, linux, windows, or unknown
detect_os() {
  case "${OSTYPE:-}" in
    darwin*)  printf 'darwin' ;;
    linux*)
      # Distinguish native Linux from WSL
      if [[ -f /proc/version ]] && grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
        printf 'windows'
      else
        printf 'linux'
      fi
      ;;
    msys*|cygwin*|mingw*) printf 'windows' ;;
    *)
      # Fallback to uname
      case "$(uname -s 2>/dev/null)" in
        Darwin)  printf 'darwin' ;;
        Linux)
          if [[ -f /proc/version ]] && grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
            printf 'windows'
          else
            printf 'linux'
          fi
          ;;
        MINGW*|MSYS*|CYGWIN*) printf 'windows' ;;
        *)  printf 'unknown' ;;
      esac
      ;;
  esac
}

# Cache the result (called once per script)
PIPELINE_OS="${PIPELINE_OS:-$(detect_os)}"

# ── Package Manager Suggestions ──────────────────────────────────────────────

# Returns a platform-appropriate install command for a given tool.
# Usage: suggest_install "gh"  →  "brew install gh" / "sudo apt install gh" / etc.
suggest_install() {
  local tool="$1"
  case "$PIPELINE_OS" in
    darwin)
      printf 'brew install %s' "$tool"
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        printf 'sudo apt install %s' "$tool"
      elif command -v dnf >/dev/null 2>&1; then
        printf 'sudo dnf install %s' "$tool"
      elif command -v pacman >/dev/null 2>&1; then
        printf 'sudo pacman -S %s' "$tool"
      elif command -v apk >/dev/null 2>&1; then
        printf 'apk add %s' "$tool"
      else
        printf 'install %s via your package manager' "$tool"
      fi
      ;;
    windows)
      if command -v choco >/dev/null 2>&1; then
        printf 'choco install %s' "$tool"
      elif command -v scoop >/dev/null 2>&1; then
        printf 'scoop install %s' "$tool"
      elif command -v winget >/dev/null 2>&1; then
        printf 'winget install %s' "$tool"
      else
        printf 'install %s via chocolatey, scoop, or winget' "$tool"
      fi
      ;;
    *)
      printf 'install %s via your package manager' "$tool"
      ;;
  esac
}

# ── Docker Start Suggestion ──────────────────────────────────────────────────

suggest_docker_start() {
  case "$PIPELINE_OS" in
    darwin)  printf 'open -a Docker' ;;
    linux)   printf 'sudo systemctl start docker' ;;
    windows) printf 'start Docker Desktop from the Start menu' ;;
    *)       printf 'start the Docker daemon' ;;
  esac
}

# ── Temp Directory ───────────────────────────────────────────────────────────
#
# Scripts that source platform.sh should use these helpers. Linter adapters
# (shared/checks/layer-2-linter/adapters/) and hooks intentionally use the
# inline pattern ${TMPDIR:-${TMP:-${TEMP:-/tmp}}} directly to avoid the
# overhead of sourcing this file on every Edit/Write hook invocation.

# Returns a safe temp directory path that works on all platforms.
pipeline_tmpdir() {
  printf '%s' "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
}

# Creates a temp file with a dev-pipeline prefix.
# Usage: tmpfile=$(pipeline_mktemp)
pipeline_mktemp() {
  mktemp "$(pipeline_tmpdir)/dev-pipeline.XXXXXX"
}

# Creates a temp directory with a dev-pipeline prefix.
# Usage: tmpdir=$(pipeline_mktempdir)
pipeline_mktempdir() {
  mktemp -d "$(pipeline_tmpdir)/dev-pipeline.XXXXXX"
}

# ── sed Compatibility ────────────────────────────────────────────────────────

# In-place sed that works on both BSD (macOS) and GNU (Linux) sed.
# Avoids the `-i` flag which differs between BSD (`-i ''`) and GNU (`-i`).
# Usage: portable_sed 's/old/new/g' file.txt
#
# Note: hooks and linter adapters intentionally do NOT source this file — they
# use inline temp-file-and-mv patterns for the same effect, avoiding the overhead
# of sourcing platform.sh on every Edit/Write or Skill invocation.
portable_sed() {
  local expr="$1" file="$2"
  local tmp
  tmp="$(pipeline_mktemp)" || { echo "portable_sed: failed to create temp file" >&2; return 1; }
  sed "$expr" "$file" > "$tmp" && mv "$tmp" "$file"
}
