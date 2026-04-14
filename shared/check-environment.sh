#!/usr/bin/env bash
# Checks for optional CLI tools that enhance Forge capabilities.
# Outputs structured JSON to stdout via Python (safe serialization).
# Always exits 0 (informational only — never blocks init).
# Does NOT detect MCP servers (that requires LLM-runtime probing, done in the skill).
set -uo pipefail

# ── Inline OS detection (same as check-prerequisites.sh) ────────────────────
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

# ── Python command (required — already validated by check-prerequisites.sh) ──
_py=""
command -v python3 >/dev/null 2>&1 && _py="python3"
[ -z "$_py" ] && command -v python >/dev/null 2>&1 && _py="python"
if [ -z "$_py" ]; then
  echo '{"error":"python not found","platform":"'"$_os"'","tools":[]}'
  exit 0
fi

# ── Probe functions ─────────────────────────────────────────────────────────
_probes=""

_probe() {
  local name="$1" tier="$2" purpose="$3" install_hint="$4"
  local available="false" version=""

  case "$name" in
    bash)
      available="true"
      version="${BASH_VERSION}"
      ;;
    python3)
      if command -v python3 >/dev/null 2>&1; then
        available="true"
        version="$(python3 --version 2>&1 | awk '{print $2}')"
      elif command -v python >/dev/null 2>&1; then
        available="true"
        version="$(python --version 2>&1 | awk '{print $2}')"
      fi
      ;;
    git)
      if command -v git >/dev/null 2>&1; then
        available="true"
        version="$(git --version 2>&1 | awk '{print $3}')"
      fi
      ;;
    jq)
      if command -v jq >/dev/null 2>&1; then
        available="true"
        version="$(jq --version 2>&1 | sed 's/jq-//' || echo 'unknown')"
      fi
      ;;
    docker)
      if command -v docker >/dev/null 2>&1; then
        available="true"
        version="$(docker --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'unknown')"
      fi
      ;;
    tree-sitter)
      if command -v tree-sitter >/dev/null 2>&1; then
        available="true"
        version="$(tree-sitter --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 'unknown')"
      fi
      ;;
    gh)
      if command -v gh >/dev/null 2>&1; then
        available="true"
        version="$(gh --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'unknown')"
      fi
      ;;
    sqlite3)
      if command -v sqlite3 >/dev/null 2>&1; then
        available="true"
        version="$(sqlite3 --version 2>&1 | awk '{print $1}' || echo 'unknown')"
      fi
      ;;
    node)
      if command -v node >/dev/null 2>&1; then
        available="true"
        version="$(node --version 2>&1 | sed 's/v//')"
      fi
      ;;
    cargo)
      if command -v cargo >/dev/null 2>&1; then
        available="true"
        version="$(cargo --version 2>&1 | awk '{print $2}')"
      fi
      ;;
    go)
      if command -v go >/dev/null 2>&1; then
        available="true"
        version="$(go version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
      fi
      ;;
  esac

  # Append as tab-separated line for safe Python parsing
  _probes="${_probes}${name}	${available}	${version}	${tier}	${purpose}	${install_hint}
"
}

# ── Install hints (platform-specific) ───────────────────────────────────────
case "$_os" in
  darwin)
    _jq_hint="brew install jq"
    _docker_hint="brew install --cask docker"
    _ts_hint="brew install tree-sitter"
    _gh_hint="brew install gh"
    _sqlite_hint="brew install sqlite3"
    ;;
  linux)
    _jq_hint="sudo apt install jq"
    _docker_hint="sudo apt install docker.io"
    _ts_hint="npm install -g tree-sitter-cli"
    _gh_hint="sudo apt install gh"
    _sqlite_hint="sudo apt install sqlite3"
    ;;
  wsl)
    _jq_hint="sudo apt install jq"
    _docker_hint="Install Docker Desktop for Windows + enable WSL2 backend"
    _ts_hint="npm install -g tree-sitter-cli"
    _gh_hint="sudo apt install gh"
    _sqlite_hint="sudo apt install sqlite3"
    ;;
  gitbash)
    _jq_hint="scoop install jq"
    _docker_hint="Install Docker Desktop from docker.com"
    _ts_hint="npm install -g tree-sitter-cli"
    _gh_hint="scoop install gh"
    _sqlite_hint="scoop install sqlite"
    ;;
  *)
    _jq_hint="https://jqlang.github.io/jq/"
    _docker_hint="https://docs.docker.com/get-docker/"
    _ts_hint="npm install -g tree-sitter-cli"
    _gh_hint="https://cli.github.com/"
    _sqlite_hint="Install sqlite3 via your package manager"
    ;;
esac

# ── Required (versions reported, prerequisites already validated) ────────────
_probe "bash" "required" "Shell runtime for Forge scripts" ""
_probe "python3" "required" "State management, JSON processing, check engine" ""
_probe "git" "required" "Version control, worktree isolation" ""

# ── Recommended (significantly improves pipeline quality) ────────────────────
_probe "jq" "recommended" "JSON processing for state management and hooks" "$_jq_hint"
_probe "docker" "recommended" "Required for Neo4j knowledge graph" "$_docker_hint"
_probe "tree-sitter" "recommended" "L0 AST-based syntax validation (PreToolUse hook)" "$_ts_hint"
_probe "gh" "recommended" "GitHub CLI for cross-repo discovery and PR creation" "$_gh_hint"
_probe "sqlite3" "recommended" "SQLite code graph (zero-dependency alternative to Neo4j)" "$_sqlite_hint"

# ── Optional (language-specific, only if project markers exist) ──────────────
if [ -f "package.json" ] || [ -f "tsconfig.json" ]; then
  _probe "node" "optional" "Node.js runtime (JS/TS project detected)" ""
fi
if [ -f "Cargo.toml" ]; then
  _probe "cargo" "optional" "Rust toolchain (Rust project detected)" ""
fi
if [ -f "go.mod" ]; then
  _probe "go" "optional" "Go toolchain (Go project detected)" ""
fi

# ── Serialize to JSON via Python (safe — no shell interpolation in JSON) ─────
echo "$_probes" | "$_py" -c "
import json, sys

tools = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split('\t')
    if len(parts) < 5:
        continue
    name, available, version, tier, purpose = parts[0], parts[1], parts[2], parts[3], parts[4]
    install = parts[5] if len(parts) > 5 else ''
    tools.append({
        'name': name,
        'available': available == 'true',
        'version': version,
        'tier': tier,
        'purpose': purpose,
        'install': install
    })

print(json.dumps({'platform': sys.argv[1], 'tools': tools}, separators=(',', ':')))
" "$_os"

exit 0
