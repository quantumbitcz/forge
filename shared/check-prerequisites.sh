#!/usr/bin/env bash
# Validates that forge plugin prerequisites are met.
# Exit 0 if all pass, exit N where N = number of failures.
set -uo pipefail

errors=0

# ── Inline OS detection (minimal, no bash 4+ features) ─────────────────────
_os="unknown"
case "${OSTYPE:-}" in
  darwin*)  _os="darwin" ;;
  linux*)
    if [ -f /proc/version ] && grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
      _os="wsl"
    else
      _os="linux"
    fi
    ;;
  msys*|cygwin*|mingw*) _os="gitbash" ;;
  *)
    case "$(uname -s 2>/dev/null)" in
      Darwin)  _os="darwin" ;;
      Linux)
        if [ -f /proc/version ] && grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
          _os="wsl"
        else
          _os="linux"
        fi
        ;;
      MINGW*|MSYS*|CYGWIN*) _os="gitbash" ;;
    esac
    ;;
esac

_suggest_bash() {
  case "$_os" in
    darwin)
      echo "  macOS:         brew install bash"
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        echo "  Debian/Ubuntu: sudo apt install bash"
      elif command -v dnf >/dev/null 2>&1; then
        echo "  Fedora/RHEL:   sudo dnf install bash"
      elif command -v pacman >/dev/null 2>&1; then
        echo "  Arch:          sudo pacman -S bash"
      elif command -v apk >/dev/null 2>&1; then
        echo "  Alpine:        apk add bash"
      else
        echo "  Linux:         install bash 4+ via your package manager"
      fi
      ;;
    wsl)
      echo "  WSL:           sudo apt install bash  (inside WSL)"
      echo "  (or update WSL distro: wsl --update)"
      ;;
    gitbash)
      echo "  Git Bash:      update Git for Windows from https://git-scm.com/download/win"
      echo "                 (includes bash 4+)"
      echo "  Alternative:   scoop install git"
      ;;
    *)
      echo "  Install bash 4+ via your package manager"
      ;;
  esac
}

_suggest_python() {
  case "$_os" in
    darwin)
      echo "  macOS:         brew install python3"
      ;;
    linux)
      if command -v apt-get >/dev/null 2>&1; then
        echo "  Debian/Ubuntu: sudo apt install python3"
      elif command -v dnf >/dev/null 2>&1; then
        echo "  Fedora/RHEL:   sudo dnf install python3"
      elif command -v pacman >/dev/null 2>&1; then
        echo "  Arch:          sudo pacman -S python"
      elif command -v apk >/dev/null 2>&1; then
        echo "  Alpine:        apk add python3"
      else
        echo "  Linux:         install python3 via your package manager"
      fi
      ;;
    wsl)
      echo "  WSL:           sudo apt install python3  (inside WSL)"
      ;;
    gitbash)
      echo "  Git Bash:      scoop install python"
      echo "  Alternative:   winget install Python.Python.3"
      echo "  Alternative:   download from https://www.python.org/downloads/windows/"
      ;;
    *)
      echo "  Install python3 via your package manager or https://www.python.org"
      ;;
  esac
}

# ── Bash 4.0+ check ───────────────────────────────────────────────────────
BASH_MAJOR="${BASH_VERSINFO[0]}"
if [ "$BASH_MAJOR" -lt 4 ]; then
  echo "ERROR: forge plugin requires bash 4.0+ (found ${BASH_VERSION})"
  _suggest_bash
  errors=$((errors + 1))
fi

# ── Python 3 check ────────────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  echo "ERROR: forge plugin requires python3 (not found)"
  _suggest_python
  errors=$((errors + 1))
fi

# ── Summary ───────────────────────────────────────────────────────────────
if [ $errors -eq 0 ]; then
  _py_cmd="python3"
  command -v python3 >/dev/null 2>&1 || _py_cmd="python"
  _py_ver=$("$_py_cmd" --version 2>&1 | awk '{print $2}')
  echo "OK: all prerequisites met (bash ${BASH_VERSION}, ${_py_cmd} ${_py_ver}, platform: ${_os})"
fi

exit "$errors"
