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

# ── WSL Detection ────────────────────────────────────────────────────────────

# Returns 0 (true) if running inside WSL, 1 (false) otherwise.
# Useful when scripts need WSL-specific behaviour beyond what detect_os provides
# (detect_os returns 'windows' for both native Windows shells and WSL).
is_wsl() {
  [[ -f /proc/version ]] && grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null
}

# ── Docker Start Suggestion ──────────────────────────────────────────────────

suggest_docker_start() {
  case "$PIPELINE_OS" in
    darwin)  printf 'open -a Docker' ;;
    linux)   printf 'sudo systemctl start docker' ;;
    windows)
      if is_wsl; then
        printf 'start Docker Desktop on the Windows host (or: powershell.exe -Command "Start-Process Docker")'
      else
        printf 'start Docker Desktop from the Start menu'
      fi
      ;;
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

# ── Path Normalisation ───────────────────────────────────────────────────────

# Resolves ./ // and .. segments in a path without touching the filesystem.
# Uses python3 when available; falls back to pure Bash (3.2+).
# Usage: normalized=$(portable_normalize_path "src/utils/../models/user.ts")
portable_normalize_path() {
  local input="$1"
  # Fast path: if no special segments, return as-is
  if [[ "$input" != *".."* && "$input" != *"./"* && "$input" != *"//"* ]]; then
    printf '%s' "$input"
    return
  fi
  # Try python3 first (handles all edge cases)
  if command -v python3 &>/dev/null; then
    python3 -c "import os.path,sys; print(os.path.normpath(sys.argv[1]))" "$input" 2>/dev/null && return
  fi
  # Bash fallback: resolve ./ // and .. segments (Bash 3.2+)
  input="${input#./}"
  while [[ "$input" == *"//"* ]]; do input="${input//\/\//\/}"; done
  local IFS='/' segment
  local -a stack=()
  local n=0 leading_dots=0
  for segment in $input; do
    case "$segment" in
      ..)
        if [[ $n -gt 0 ]]; then
          n=$((n - 1))
        else
          leading_dots=$((leading_dots + 1))
        fi
        ;;
      .|'') ;;
      *) stack[$n]="$segment"; n=$((n + 1)) ;;
    esac
  done
  local result="" i
  for ((i = 0; i < leading_dots; i++)); do
    result="${result:+$result/}.."
  done
  for ((i = 0; i < n; i++)); do
    result="${result:+$result/}${stack[$i]}"
  done
  printf '%s' "$result"
}

# ── Portable File Date ──────────────────────────────────────────────────────

# Returns the last-modified date (YYYY-MM-DD) for a file, cross-platform.
# Cascade: BSD stat → GNU stat+date → perl → python3 → git log → today.
# Usage: mod_date=$(portable_file_date "/absolute/path/to/file")
portable_file_date() {
  local filepath="$1"
  # 1. BSD stat (macOS)
  stat -f '%Sm' -t '%Y-%m-%d' "$filepath" 2>/dev/null && return
  # 2. GNU stat + GNU date
  local epoch
  epoch=$(stat -c '%Y' "$filepath" 2>/dev/null) && {
    date -d "@$epoch" '+%Y-%m-%d' 2>/dev/null && return
    # 3. perl (widely available, lighter than python3)
    perl -e "use POSIX qw(strftime); print strftime('%Y-%m-%d', localtime($epoch))" 2>/dev/null && return
    # 4. python3
    python3 -c "import datetime; print(datetime.datetime.utcfromtimestamp($epoch).strftime('%Y-%m-%d'))" 2>/dev/null && return
  }
  # 5. git log (works in any git repo)
  git log -1 --format='%as' -- "$filepath" 2>/dev/null && return
  # 6. Ultimate fallback: today
  date '+%Y-%m-%d'
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
