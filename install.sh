#!/usr/bin/env bash
# forge plugin installer for macOS and Linux.
# Windows users: use install.ps1 instead.
set -euo pipefail

FORGE_REPO="${FORGE_REPO:-https://github.com/quantumbitcz/forge.git}"
FORGE_REF="${FORGE_REF:-master}"
PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.claude/plugins/forge}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: install.sh [--dry-run] [--help]

Installs the forge plugin into $HOME/.claude/plugins/forge.

Env overrides:
  FORGE_REPO  git URL            (default: quantumbitcz/forge on GitHub)
  FORGE_REF   git ref to check out (default: master)
  PLUGIN_DIR  install destination (default: $HOME/.claude/plugins/forge)

Options:
  --dry-run   Print planned actions without writing anything.
  --help      Show this message and exit.
USAGE
}

log()   { printf '[install.sh] %s\n' "$*"; }
warn()  { printf '[install.sh] WARN: %s\n' "$*" >&2; }
error() { printf '[install.sh] ERROR: %s\n' "$*" >&2; exit 1; }

while (( "$#" )); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) error "unknown arg: $1 (try --help)" ;;
  esac
done

command -v git >/dev/null 2>&1 || error "git is required but not in PATH"

if (( DRY_RUN )); then
  log "dry-run: would ensure $PLUGIN_DIR exists"
  log "dry-run: would clone $FORGE_REPO ref $FORGE_REF into $PLUGIN_DIR"
  log "dry-run: would add plugin entry to $HOME/.claude/settings.json"
  exit 0
fi

mkdir -p "$(dirname "$PLUGIN_DIR")"

if [ -d "$PLUGIN_DIR/.git" ]; then
  log "updating existing clone at $PLUGIN_DIR"
  git -C "$PLUGIN_DIR" fetch --depth 1 origin "$FORGE_REF"
  git -C "$PLUGIN_DIR" checkout "$FORGE_REF"
  git -C "$PLUGIN_DIR" reset --hard "origin/$FORGE_REF"
else
  log "cloning $FORGE_REPO into $PLUGIN_DIR"
  git clone --depth 1 --branch "$FORGE_REF" "$FORGE_REPO" "$PLUGIN_DIR"
fi

SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
  printf '{"plugins":["%s"]}\n' "$PLUGIN_DIR" > "$SETTINGS"
  log "created $SETTINGS with plugin entry"
else
  if grep -q "$PLUGIN_DIR" "$SETTINGS"; then
    log "$SETTINGS already references $PLUGIN_DIR"
  else
    warn "$SETTINGS exists; please add \"$PLUGIN_DIR\" to the \"plugins\" array manually"
  fi
fi

log "done. Run /forge-init in a project to complete setup."
