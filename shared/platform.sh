#!/usr/bin/env bash
# Cross-platform detection helpers for forge scripts.
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
FORGE_OS="${FORGE_OS:-$(detect_os)}"

# ── Package Manager Suggestions ──────────────────────────────────────────────

# Returns a platform-appropriate install command for a given tool.
# Usage: suggest_install "gh"  →  "brew install gh" / "sudo apt install gh" / etc.
suggest_install() {
  local tool="$1"
  case "$FORGE_OS" in
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
  case "$FORGE_OS" in
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

# ── Bash Version Check ───────────────────────────────────────────────────────
#
# Scripts using associative arrays (declare -A) require bash 4.0+.
# macOS ships with bash 3.2 by default; Homebrew bash is the norm for
# developers but CI runners and fresh installs may hit this.
#
# Usage: require_bash4 "build-project-graph.sh"

require_bash4() {
  local caller="${1:-script}"
  if (( BASH_VERSINFO[0] < 4 )); then
    printf 'ERROR: %s requires bash 4.0+ (found %s).\n' "$caller" "$BASH_VERSION" >&2
    printf '  macOS: brew install bash\n' >&2
    printf '  Linux: bash 4+ is standard on all modern distributions.\n' >&2
    return 1
  fi
}

# ── Portable Glob Matching ────────────────────────────────────────────────────
#
# Returns 0 if any file matches the glob pattern, 1 otherwise.
# Replaces compgen -G (a bash builtin not available on all platforms).
#
# Scripts that source platform.sh should use this. Performance-critical paths
# (engine.sh) keep an inline copy to avoid the overhead of sourcing platform.sh
# on every PostToolUse hook invocation.
#
# Usage: _glob_exists "/path/to/dir"/*.ext

_glob_exists() {
  local pattern="$1"
  local f
  for f in $pattern; do
    [ -e "$f" ] && return 0
  done
  return 1
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

# Creates a temp file with a forge prefix.
# Usage: tmpfile=$(pipeline_mktemp)
pipeline_mktemp() {
  mktemp "$(pipeline_tmpdir)/forge.XXXXXX"
}

# Creates a temp directory with a forge prefix.
# Usage: tmpdir=$(pipeline_mktempdir)
pipeline_mktempdir() {
  mktemp -d "$(pipeline_tmpdir)/forge.XXXXXX"
}

# ── Python Detection ─────────────────────────────────────────────────────

# Returns the available python command name (python3 or python).
# Cached in FORGE_PYTHON for reuse. Scripts that source platform.sh should
# use "$FORGE_PYTHON" instead of hardcoding "python3".
# Scripts that do NOT source platform.sh (engine.sh, run-patterns.sh,
# linter adapters, hooks) should use inline fallback or direct python3
# calls — python3 is available on all major platforms (macOS, modern
# Linux, Windows with Python installed). These scripts avoid sourcing
# platform.sh due to invocation frequency (every Edit/Write hook).
detect_python() {
  if command -v python3 &>/dev/null; then
    printf 'python3'
  elif command -v python &>/dev/null; then
    printf 'python'
  else
    printf ''
  fi
}

FORGE_PYTHON="${FORGE_PYTHON:-$(detect_python)}"

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
  # Try Python first (handles all edge cases)
  if [[ -n "$FORGE_PYTHON" ]]; then
    "$FORGE_PYTHON" -c "import os.path,sys; print(os.path.normpath(sys.argv[1]))" "$input" 2>/dev/null && return
  fi
  # Bash fallback: resolve ./ // and .. segments (Bash 3.2+)
  local is_absolute=0
  [[ "$input" == /* ]] && is_absolute=1 && input="${input#/}"
  input="${input#./}"
  while [[ "$input" == *"//"* ]]; do input="${input//\/\//\/}"; done
  local IFS='/' segment
  local -a stack=()
  local n=0 leading_dots=0
  # shellcheck disable=SC2004  # explicit $n for bash 3.2 compat
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
  # For absolute paths, leading .. above root is discarded (can't go above /)
  [[ $is_absolute -eq 1 ]] && leading_dots=0
  local result="" i
  for ((i = 0; i < leading_dots; i++)); do
    result="${result:+$result/}.."
  done
  for ((i = 0; i < n; i++)); do
    result="${result:+$result/}${stack[$i]}"
  done
  [[ $is_absolute -eq 1 ]] && result="/$result"
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
    # 4. python3 or python (via FORGE_PYTHON)
    [[ -n "$FORGE_PYTHON" ]] && "$FORGE_PYTHON" -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), tz=datetime.timezone.utc).strftime('%Y-%m-%d'))" "$epoch" 2>/dev/null && return
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
  if sed "$expr" "$file" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    echo "portable_sed: sed expression failed" >&2
    return 1
  fi
}

# ── timeout Compatibility ───────────────────────────────────────────────────

# Cross-platform timeout wrapper. Uses GNU timeout, then macOS gtimeout
# (from coreutils), then falls back to running without a timeout.
# Usage: portable_timeout <seconds> <command> [args...]
portable_timeout() {
  local seconds="${1:?portable_timeout: missing seconds argument}"; shift
  if command -v timeout &>/dev/null; then
    timeout "$seconds" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$seconds" "$@"
  else
    # No timeout available — run without time limit
    "$@"
  fi
}

# ── Project Identity ─────────────────────────────────────────────────────────

# Derives project_id from git remote origin, fallback to absolute path.
# Usage: project_id=$(derive_project_id "/path/to/project")
derive_project_id() {
  local project_root="${1:-.}"
  local remote_url
  remote_url=$(git -C "$project_root" remote get-url origin 2>/dev/null || true)
  if [[ -n "$remote_url" ]]; then
    # Strip protocol/host prefix and .git suffix
    # Handles: git@github.com:org/repo.git, https://github.com/org/repo.git, ssh://...
    echo "$remote_url" | sed -E 's|^.*[:/]([^/]+/[^/]+?)(\.git)?$|\1|'
  else
    # Fallback: absolute path
    (cd "$project_root" && pwd)
  fi
}

# Read component names from forge.local.md components: section.
# Returns one component name per line. Empty output for single-component projects.
# Usage: while IFS= read -r comp; do echo "$comp"; done < <(read_components "/path/to/project")
read_components() {
  local project_root="${1:-.}"
  local config_file="${project_root}/.claude/forge.local.md"
  if [[ ! -f "$config_file" ]]; then
    return
  fi
  # Extract component names (2-space indented keys under components:)
  awk '/^components:/{found=1; next} found && /^  [a-zA-Z]/{sub(/:.*/, ""); print $1; next} found && /^[^ ]/{exit}' "$config_file"
}

# ── Atomic Operations ───────────────────────────────────────────────────────
#
# Thread-safe primitives for hooks and scripts. Uses flock (Linux) with
# mkdir-based fallback (macOS/bash 3.2). Hooks that do NOT source platform.sh
# should use inline patterns instead.

# Atomic increment of a counter file.
# Usage: atomic_increment "/path/to/counter.file"
# Returns: new value on stdout. Exit 1 on lock timeout.
# Thread-safe via flock (Linux) or mkdir-lock (macOS).
atomic_increment() {
  local file="$1"
  local lock_file="${file}.lock"
  local new_val

  if command -v flock &>/dev/null; then
    (
      flock -w 5 9 || { echo "0"; return 1; }
      local count=0
      [ -f "$file" ] && count=$(cat "$file" 2>/dev/null || echo 0)
      # Guard against non-numeric content
      [[ "$count" =~ ^[0-9]+$ ]] || count=0
      new_val=$((count + 1))
      echo "$new_val" > "$file"
      echo "$new_val"
    ) 9>"$lock_file"
  else
    # macOS fallback: mkdir-based lock
    local lock_dir="${file}.lockdir"
    local retries=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
      retries=$((retries + 1))
      [ "$retries" -ge 50 ] && { echo "0"; return 1; }
      sleep 0.1
    done
    trap "rmdir '$lock_dir' 2>/dev/null || rm -rf '$lock_dir' 2>/dev/null" RETURN
    local count=0
    [ -f "$file" ] && count=$(cat "$file" 2>/dev/null || echo 0)
    # Guard against non-numeric content
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    new_val=$((count + 1))
    echo "$new_val" > "$file"
    echo "$new_val"
  fi
}

# Atomic read-modify-write of a JSON file via Python.
# Usage: atomic_json_update "/path/to/file.json" "python_expression"
# The python expression receives 'data' (parsed JSON dict) and should mutate it in-place.
# Example: atomic_json_update state.json "data['lastCheckpoint'] = '2026-01-01T00:00:00Z'"
# Exit 1 on failure (lock timeout, missing file, invalid JSON, no python).
atomic_json_update() {
  local file="$1"
  local py_expr="$2"
  local lock_file="${file}.lock"
  local tmp

  _do_update() {
    local _py=""
    command -v python3 &>/dev/null && _py="python3"
    [ -z "$_py" ] && command -v python &>/dev/null && _py="python"
    [ -z "$_py" ] && return 1

    tmp=$(mktemp "${TMPDIR:-/tmp}/forge-atomic.XXXXXX")

    "$_py" -c "
import json, sys, os
with open(sys.argv[1]) as f:
    data = json.load(f)
$py_expr
with open(sys.argv[2], 'w') as f:
    json.dump(data, f, indent=2)
" "$file" "$tmp" && mv "$tmp" "$file"
    local rc=$?
    rm -f "$tmp" 2>/dev/null
    return $rc
  }

  if command -v flock &>/dev/null; then
    (
      flock -w 5 9 || return 1
      _do_update
    ) 9>"$lock_file"
  else
    local lock_dir="${file}.lockdir"
    local retries=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
      retries=$((retries + 1))
      [ "$retries" -ge 50 ] && return 1
      sleep 0.1
    done
    trap "rmdir '$lock_dir' 2>/dev/null || rm -rf '$lock_dir' 2>/dev/null" RETURN
    _do_update
  fi
}
