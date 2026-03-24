#!/usr/bin/env bash
# Cross-repo project discovery for dev-pipeline
# Usage: discover-projects.sh <project-root> [--depth N]
# Output: JSON array of discovered related projects

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_TYPE="$SCRIPT_DIR/detect-project-type.sh"

# Source platform helpers
# shellcheck source=../platform.sh
source "$SCRIPT_DIR/../platform.sh"

PROJECT_ROOT="${1:-$(pwd)}"
DEPTH=2

# Parse optional --depth flag
while [[ $# -gt 0 ]]; do
  case "$1" in
    --depth) shift; DEPTH="${1:-2}" ;;
    --depth=*) DEPTH="${1#*=}" ;;
  esac
  shift 2>/dev/null || true
done

# Normalize depth to integer
DEPTH=$(( DEPTH + 0 )) 2>/dev/null || DEPTH=2

# ── Helpers ───────────────────────────────────────────────────────────────────

results=()   # accumulates JSON objects as strings
seen_paths=() # dedup by absolute path

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

add_result() {
  local name="$1" path="$2" repo="$3" type="$4" framework="$5" detected_via="$6" confidence="$7"
  # Deduplicate by path
  local p
  for p in "${seen_paths[@]+"${seen_paths[@]}"}"; do
    [[ "$p" == "$path" ]] && return 0
  done
  seen_paths+=("$path")
  results+=("$(printf '{"name":"%s","path":"%s","repo":"%s","type":"%s","framework":"%s","detected_via":"%s","confidence":"%s"}' \
    "$(json_escape "$name")" "$(json_escape "$path")" "$(json_escape "$repo")" \
    "$(json_escape "$type")" "$(json_escape "$framework")" \
    "$(json_escape "$detected_via")" "$(json_escape "$confidence")")")
}

detect_type_and_framework() {
  local dir="$1"
  if [[ -x "$DETECT_TYPE" ]]; then
    "$DETECT_TYPE" "$dir" 2>/dev/null || printf '{"type":"unknown","framework":"unknown","language":"unknown"}'
  else
    printf '{"type":"unknown","framework":"unknown","language":"unknown"}'
  fi
}

extract_json_field() {
  local json="$1" field="$2"
  printf '%s' "$json" | grep -o "\"$field\":\"[^\"]*\"" | cut -d'"' -f4 || true
}

get_git_remote() {
  local dir="$1"
  git -C "$dir" remote get-url origin 2>/dev/null || true
}

normalize_repo_url() {
  local url="$1"
  # Strip ssh prefix, trailing .git, etc.
  url="${url#git@}"
  url="${url#https://}"
  url="${url%.git}"
  url="${url/://}"   # git@github.com:org/repo -> github.com/org/repo
  printf '%s' "$url"
}

get_org_from_remote() {
  local remote="$1"
  # github.com/org/repo -> org
  printf '%s' "$remote" | sed 's|.*/\([^/]*\)/[^/]*$|\1|' 2>/dev/null || true
}

process_candidate() {
  local dir="$1" detected_via="$2" confidence="$3"
  [[ -d "$dir/.git" || -f "$dir/.git" ]] || return 0
  local abs_dir
  abs_dir="$(cd "$dir" && pwd)"
  local name
  name="$(basename "$abs_dir")"
  local remote
  remote="$(get_git_remote "$abs_dir")"
  local repo=""
  [[ -n "$remote" ]] && repo="$(normalize_repo_url "$remote")"

  local detection
  detection="$(detect_type_and_framework "$abs_dir")"
  local type framework
  type="$(extract_json_field "$detection" "type")"
  framework="$(extract_json_field "$detection" "framework")"

  [[ "$type" == "unknown" ]] && return 0  # skip unrecognizable dirs

  add_result "$name" "$abs_dir" "$repo" "$type" "$framework" "$detected_via" "$confidence"
}

# ── Step 1: In-project references ────────────────────────────────────────────

step1_inproject_references() {
  local root="$1"
  local candidate_paths=()

  # README, CONTRIBUTING — local relative paths that look like sibling dirs
  for f in "$root/README.md" "$root/CONTRIBUTING.md" "$root/CLAUDE.md"; do
    [[ -f "$f" ]] || continue
    # Extract lines containing sibling-like path refs (../something)
    while IFS= read -r line; do
      local relpath
      relpath="$(printf '%s' "$line" | grep -oE '\.\./[a-zA-Z0-9_.-]+' | head -1 || true)"
      if [[ -n "$relpath" ]]; then
        local abs
        abs="$(cd "$root" && cd "$relpath" 2>/dev/null && pwd || true)"
        [[ -n "$abs" && -d "$abs" ]] && candidate_paths+=("$abs:readme-reference:medium")
      fi
    done < "$f"
  done

  # docker-compose: build contexts
  for f in "$root/docker-compose.yml" "$root/docker-compose.yaml"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
      local ctx
      ctx="$(printf '%s' "$line" | grep -oE 'context:\s*\S+' | awk '{print $2}' | head -1 || true)"
      if [[ -n "$ctx" && "$ctx" != "." ]]; then
        local abs
        abs="$(cd "$root" && cd "$ctx" 2>/dev/null && pwd || true)"
        [[ -n "$abs" && -d "$abs" ]] && candidate_paths+=("$abs:docker-compose:high")
      fi
    done < "$f"
  done

  # .github/workflows — repository references in checkout actions
  if [[ -d "$root/.github/workflows" ]]; then
    while IFS= read -r line; do
      local repo_ref
      repo_ref="$(printf '%s' "$line" | grep -oE "repository:\s*['\"]?[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+" \
        | sed "s/repository:\s*['\"]*//" | head -1 || true)"
      if [[ -n "$repo_ref" ]]; then
        # Try to resolve to a local path via git remote matching
        local sibling_name
        sibling_name="$(basename "$repo_ref")"
        local parent
        parent="$(dirname "$root")"
        [[ -d "$parent/$sibling_name" ]] && candidate_paths+=("$parent/$sibling_name:github-workflow:high")
      fi
    done < <(grep -rh "repository:" "$root/.github/workflows/" 2>/dev/null || true)
  fi

  # .env / .env.example — *_REPO or *_URL variables pointing to sibling names
  for f in "$root/.env" "$root/.env.example"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
      local val
      val="$(printf '%s' "$line" | grep -E '^[A-Z_]+(REPO|URL)=' | cut -d= -f2- | tr -d '"' || true)"
      if [[ -n "$val" ]]; then
        local sibling_name
        sibling_name="$(basename "$val" .git)"
        local parent
        parent="$(dirname "$root")"
        [[ -d "$parent/$sibling_name" ]] && candidate_paths+=("$parent/$sibling_name:env-file:medium")
      fi
    done < "$f"
  done

  # package.json workspaces
  if [[ -f "$root/package.json" ]]; then
    while IFS= read -r line; do
      local ws
      ws="$(printf '%s' "$line" | grep -oE '"[a-zA-Z0-9_/.-]+"' | tr -d '"' || true)"
      if [[ -n "$ws" ]]; then
        local abs
        abs="$(cd "$root" && cd "$ws" 2>/dev/null && pwd || true)"
        [[ -n "$abs" && -d "$abs" && "$abs" != "$root" ]] && candidate_paths+=("$abs:package-workspace:high")
      fi
    done < <(python3 -c "
import json,sys
try:
  d=json.load(open('$root/package.json'))
  ws=d.get('workspaces',[])
  if isinstance(ws,dict): ws=ws.get('packages',[])
  [print(w) for w in ws]
except: pass
" 2>/dev/null || true)
  fi

  # build.gradle.kts composite builds
  if [[ -f "$root/settings.gradle.kts" ]]; then
    while IFS= read -r line; do
      local inc
      inc="$(printf '%s' "$line" | grep -oE 'includeBuild\s*\(["\x27][^"\x27]+["\x27]\)' \
        | grep -oE '"[^"]+"|'"'"'[^'"'"']+'"'" | tr -d '"'"'" || true)"
      if [[ -n "$inc" ]]; then
        local abs
        abs="$(cd "$root" && cd "$inc" 2>/dev/null && pwd || true)"
        [[ -n "$abs" && -d "$abs" ]] && candidate_paths+=("$abs:gradle-composite:high")
      fi
    done < "$root/settings.gradle.kts"
  fi

  for entry in "${candidate_paths[@]+"${candidate_paths[@]}"}"; do
    local dir="${entry%%:*}"
    local rest="${entry#*:}"
    local via="${rest%%:*}"
    local conf="${rest##*:}"
    process_candidate "$dir" "$via" "$conf"
  done
}

# ── Step 2: Sibling directory scan ───────────────────────────────────────────

step2_sibling_scan() {
  local root="$1"
  local parent
  parent="$(dirname "$root")"
  local current_name
  current_name="$(basename "$root")"
  local current_remote
  current_remote="$(get_git_remote "$root")"
  local current_org=""
  [[ -n "$current_remote" ]] && current_org="$(get_org_from_remote "$(normalize_repo_url "$current_remote")")"

  # Derive prefix: strip common suffixes (be, fe, infra, mobile, ios, android, api, web, app)
  local prefix
  prefix="$(printf '%s' "$current_name" | sed -E 's/[-_]?(be|fe|backend|frontend|infra|mobile|ios|android|api|web|app|server|client|ui|admin)$//i')"
  [[ ${#prefix} -lt 2 ]] && prefix="$current_name"

  local sibling
  for sibling in "$parent"/*/; do
    [[ -d "$sibling" ]] || continue
    local sname
    sname="$(basename "$sibling")"
    [[ "$sname" == "$current_name" ]] && continue

    local confidence="low"

    # Same prefix match
    if [[ "$sname" == "${prefix}"* || "$sname" == *"${prefix}" ]]; then
      confidence="high"
    fi

    # Same git org match (even if prefix differs)
    if [[ "$confidence" != "high" && -n "$current_org" ]]; then
      local sremote
      sremote="$(get_git_remote "$sibling" 2>/dev/null || true)"
      if [[ -n "$sremote" ]]; then
        local sorg
        sorg="$(get_org_from_remote "$(normalize_repo_url "$sremote")")"
        [[ "$sorg" == "$current_org" ]] && confidence="medium"
      fi
    fi

    [[ "$confidence" == "low" ]] && continue

    process_candidate "$sibling" "sibling-directory" "$confidence"
  done
}

# ── Step 3: IDE project directories ──────────────────────────────────────────

step3_ide_directories() {
  local root="$1"
  local current_name
  current_name="$(basename "$root")"
  local current_remote
  current_remote="$(get_git_remote "$root")"
  local current_org=""
  [[ -n "$current_remote" ]] && current_org="$(get_org_from_remote "$(normalize_repo_url "$current_remote")")"

  local prefix
  prefix="$(printf '%s' "$current_name" | sed -E 's/[-_]?(be|fe|backend|frontend|infra|mobile|ios|android|api|web|app|server|client|ui|admin)$//i')"
  [[ ${#prefix} -lt 2 ]] && prefix="$current_name"

  local ide_dirs=()
  local home="${HOME:-/tmp}"

  # IDE project directories: JetBrains (IntelliJ, WebStorm, PyCharm, GoLand, CLion, Rider,
  # Android Studio, RustRover, PhpStorm, DataGrip, DataSpell, AppCode, Fleet, Aqua, Wright),
  # VS Code, Cursor, Windsurf, Zed, Xcode, Eclipse, NetBeans, plus generic conventions.
  for d in \
    "$home/IdeaProjects" "$home/WebstormProjects" "$home/PycharmProjects" \
    "$home/GolandProjects" "$home/CLionProjects" "$home/RiderProjects" \
    "$home/AndroidStudioProjects" "$home/RustroverProjects" \
    "$home/PhpstormProjects" "$home/DataGripProjects" "$home/DataSpellProjects" \
    "$home/AppCodeProjects" "$home/FleetProjects" "$home/AquaProjects" \
    "$home/WrightProjects" \
    "$home/VSCodeProjects" "$home/vscode-projects" \
    "$home/CursorProjects" "$home/cursor-projects" \
    "$home/WindsurfProjects" "$home/ZedProjects" \
    "$home/XcodeProjects" \
    "$home/eclipse-workspace" "$home/NetBeansProjects" \
    "$home/Projects" "$home/Developer" "$home/Development" \
    "$home/workspace" "$home/Workspace" \
    "$home/repos" "$home/Repos" "$home/git" "$home/src" "$home/code" \
    "$home/Code"; do
    [[ -d "$d" ]] && ide_dirs+=("$d")
  done

  # Platform-specific paths (skip irrelevant checks per OS)
  if [[ "$PIPELINE_OS" == "windows" ]]; then
    # Windows: Documents, Visual Studio, GitHub Desktop, drive roots
    for d in "$home/Documents/Projects" "$home/Documents/repos" \
             "$home/Documents/Visual Studio 2022/Projects" \
             "$home/Documents/Visual Studio 2019/Projects" \
             "$home/Documents/Visual Studio Code Projects" \
             "$home/Documents/GitHub" "$home/Documents/source/repos" \
             "$home/source/repos"; do
      [[ -d "$d" ]] && ide_dirs+=("$d")
    done
    for drv in /c /d /e C: D: E:; do
      for d in "$drv/dev" "$drv/projects" "$drv/repos" "$drv/src" "$drv/code" "$drv/git"; do
        [[ -d "$d" ]] && ide_dirs+=("$d")
      done
    done
  fi

  if [[ "$PIPELINE_OS" == "linux" ]]; then
    # Linux: lowercase conventions common on Linux desktops
    for d in "$home/projects" "$home/dev" "$home/devel"; do
      [[ -d "$d" ]] && ide_dirs+=("$d")
    done
  fi

  for ide_dir in "${ide_dirs[@]+"${ide_dirs[@]}"}"; do
    local project
    for project in "$ide_dir"/*/; do
      [[ -d "$project" ]] || continue
      local pname
      pname="$(basename "$project")"
      [[ "$pname" == "$current_name" ]] && continue

      local confidence="low"

      # Prefix match
      if [[ "$pname" == "${prefix}"* || "$pname" == *"${prefix}" ]]; then
        confidence="high"
      fi

      # Org match
      if [[ "$confidence" != "high" && -n "$current_org" ]]; then
        local premote
        premote="$(get_git_remote "$project" 2>/dev/null || true)"
        if [[ -n "$premote" ]]; then
          local porg
          porg="$(get_org_from_remote "$(normalize_repo_url "$premote")")"
          [[ "$porg" == "$current_org" ]] && confidence="medium"
        fi
      fi

      [[ "$confidence" == "low" ]] && continue

      process_candidate "$project" "ide-directory" "$confidence"
    done
  done
}

# ── Step 4: GitHub org scan ───────────────────────────────────────────────────

step4_github_org_scan() {
  local root="$1"
  command -v gh >/dev/null 2>&1 || return 0

  local current_remote
  current_remote="$(get_git_remote "$root")"
  [[ -z "$current_remote" ]] && return 0

  local norm_remote
  norm_remote="$(normalize_repo_url "$current_remote")"
  local org
  org="$(get_org_from_remote "$norm_remote")"
  [[ -z "$org" ]] && return 0

  local current_name
  current_name="$(basename "$root")"
  local prefix
  prefix="$(printf '%s' "$current_name" | sed -E 's/[-_]?(be|fe|backend|frontend|infra|mobile|ios|android|api|web|app|server|client|ui|admin)$//i')"
  [[ ${#prefix} -lt 2 ]] && prefix="$current_name"

  local repos_json
  repos_json="$(gh repo list "$org" --json name,description --limit 50 2>/dev/null || true)"
  [[ -z "$repos_json" ]] && return 0

  # Extract repo names that match prefix (simple grep approach)
  while IFS= read -r repo_name; do
    [[ "$repo_name" == "$current_name" ]] && continue
    [[ "$repo_name" == "${prefix}"* || "$repo_name" == *"${prefix}" ]] || continue

    # Check if already found locally
    local host
    host="$(printf '%s' "$norm_remote" | cut -d/ -f1)"
    local remote_path="$host/$org/$repo_name"

    # Already in results? skip
    local found=false
    local p
    for p in "${seen_paths[@]+"${seen_paths[@]}"}"; do
      [[ "$(get_git_remote "$p" 2>/dev/null | xargs -I{} sh -c 'echo {}' | sed 's|git@||;s|https://||;s|\.git$||;s|:|/|')" == "$remote_path" ]] && found=true
    done
    $found && continue

    add_result "$repo_name" "" "$remote_path" "unknown" "unknown" "github-org" "medium"
  done < <(printf '%s' "$repos_json" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 || true)
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  [[ ! -d "$PROJECT_ROOT" ]] && printf '[]\n' && exit 0

  PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

  # Step 1 always runs
  step1_inproject_references "$PROJECT_ROOT" 2>/dev/null || true

  # Step 2 always runs
  step2_sibling_scan "$PROJECT_ROOT" 2>/dev/null || true

  # Step 3 only at depth >= 3
  if (( DEPTH >= 3 )); then
    step3_ide_directories "$PROJECT_ROOT" 2>/dev/null || true
  fi

  # Step 4 only at depth >= 4
  if (( DEPTH >= 4 )); then
    step4_github_org_scan "$PROJECT_ROOT" 2>/dev/null || true
  fi

  # Emit JSON array
  if [[ ${#results[@]} -eq 0 ]]; then
    printf '[]\n'
  else
    printf '[\n'
    local i
    for i in "${!results[@]}"; do
      if (( i < ${#results[@]} - 1 )); then
        printf '  %s,\n' "${results[$i]}"
      else
        printf '  %s\n' "${results[$i]}"
      fi
    done
    printf ']\n'
  fi
}

main
