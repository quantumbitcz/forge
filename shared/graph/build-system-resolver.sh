#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# build-system-resolver.sh -- Build System Introspection Layer
#
# Queries project build tools (mvn/gradle/cargo/go/npm/dotnet) for
# authoritative dependency and module data. Falls back to heuristic
# parsing when build tools are unavailable or fail.
#
# Usage:
#   ./shared/graph/build-system-resolver.sh \
#       --project-root /path/to/project \
#       [--output-format json|cypher] \
#       [--timeout 60] \
#       [--force-refresh]
#
# Output (json mode):  JSON to stdout
# Output (cypher mode): Cypher statements to stdout (for Neo4j)
# Exit 0 on success, 0 on graceful degradation (build tool missing)
# ============================================================================

# Support --source-only for unit testing (source functions without executing main)
if [[ "${1:-}" == "--source-only" ]]; then
  _SOURCE_ONLY=true
  shift
else
  _SOURCE_ONLY=false
fi

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../platform.sh
source "${PLUGIN_ROOT}/shared/platform.sh"

require_bash4 "build-system-resolver.sh" || exit 1

# -- Defaults ----------------------------------------------------------------

PROJECT_ROOT=""
OUTPUT_FORMAT="json"
INTROSPECTION_TIMEOUT=60
FORCE_REFRESH=false
CACHE_ENABLED=true
FALLBACK_MODE="heuristic"

# -- Argument parsing --------------------------------------------------------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root)   PROJECT_ROOT="$2"; shift 2 ;;
      --output-format)  OUTPUT_FORMAT="$2"; shift 2 ;;
      --timeout)        INTROSPECTION_TIMEOUT="$2"; shift 2 ;;
      --force-refresh)  FORCE_REFRESH=true; shift ;;
      *)
        echo "Error: Unknown argument: $1" >&2
        echo "Usage: build-system-resolver.sh --project-root /path [--output-format json|cypher] [--timeout 60] [--force-refresh]" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$PROJECT_ROOT" ]]; then
    echo "Error: --project-root is required" >&2
    exit 1
  fi

  PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
}

# -- Read config from forge-config.md if present -----------------------------

read_config() {
  local config_file="${PROJECT_ROOT}/.claude/forge-admin config.md"
  [[ -f "$config_file" && -n "${FORGE_PYTHON:-}" ]] || return 0

  eval "$("$FORGE_PYTHON" -c "
import re, sys

content = open(sys.argv[1]).read()
m = re.search(r'build_graph:\s*\n((?:[ \t]+\S.*\n)*)', content)
if not m:
    sys.exit(0)
block = m.group(1)
for line in block.strip().split('\n'):
    line = line.strip()
    if ':' not in line:
        continue
    key, _, val = line.partition(':')
    key = key.strip()
    val = val.strip().strip('\"').strip(\"'\")
    if key == 'introspection' and val in ('false', 'False', 'no'):
        print('INTROSPECTION_ENABLED=false')
    elif key == 'introspection_timeout_seconds' and val.isdigit():
        print(f'INTROSPECTION_TIMEOUT={val}')
    elif key == 'cache_enabled' and val in ('false', 'False', 'no'):
        print(f'CACHE_ENABLED=false')
    elif key == 'fallback' and val in ('heuristic', 'skip'):
        print(f'FALLBACK_MODE={val}')
" "$config_file" 2>/dev/null || true)"
}

# -- Detection ---------------------------------------------------------------

detect_build_systems() {
  local root="$1"
  local systems=()

  # Maven: pom.xml at root
  [[ -f "$root/pom.xml" ]] && systems+=("maven")

  # Gradle: build.gradle(.kts) is sufficient for detection.
  # settings.gradle(.kts) presence determines single-module vs multi-module mode,
  # but is NOT required for detection.
  if [[ -f "$root/build.gradle" || -f "$root/build.gradle.kts" ]]; then
    systems+=("gradle")
  fi

  # npm/pnpm/yarn: package.json at root
  if [[ -f "$root/package.json" ]]; then
    if [[ -f "$root/pnpm-lock.yaml" || -f "$root/pnpm-workspace.yaml" ]]; then
      systems+=("pnpm")
    elif [[ -f "$root/yarn.lock" ]]; then
      systems+=("yarn")
    else
      systems+=("npm")
    fi
  fi

  # Go: go.mod or go.work
  [[ -f "$root/go.mod" || -f "$root/go.work" ]] && systems+=("go")

  # Cargo: Cargo.toml
  [[ -f "$root/Cargo.toml" ]] && systems+=("cargo")

  # .NET: *.sln or *.csproj at root
  if _glob_exists "$root"/*.sln || _glob_exists "$root"/*.csproj; then
    systems+=("dotnet")
  fi

  printf '%s\n' "${systems[@]}"
}

# -- Cache -------------------------------------------------------------------

CACHE_FILE=""

compute_build_file_hashes() {
  local system="$1" root="$2"
  local files=()

  case "$system" in
    maven)
      while IFS= read -r f; do files+=("$f"); done < <(find "$root" -name "pom.xml" -not -path "*/target/*" -not -path "*/.git/*" 2>/dev/null | sort)
      ;;
    gradle)
      for pattern in "settings.gradle" "settings.gradle.kts" "build.gradle" "build.gradle.kts" "gradle.properties" "gradle/libs.versions.toml"; do
        while IFS= read -r f; do files+=("$f"); done < <(find "$root" -name "$(basename "$pattern")" -not -path "*/build/*" -not -path "*/.git/*" -not -path "*/.gradle/*" 2>/dev/null | sort)
      done
      ;;
    npm|pnpm|yarn)
      while IFS= read -r f; do files+=("$f"); done < <(find "$root" -name "package.json" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | sort)
      for lf in "package-lock.json" "pnpm-lock.yaml" "yarn.lock"; do
        [[ -f "$root/$lf" ]] && files+=("$root/$lf")
      done
      ;;
    go)
      while IFS= read -r f; do files+=("$f"); done < <(find "$root" -name "go.mod" -o -name "go.sum" -o -name "go.work" 2>/dev/null | sort)
      ;;
    cargo)
      while IFS= read -r f; do files+=("$f"); done < <(find "$root" -name "Cargo.toml" -o -name "Cargo.lock" 2>/dev/null | grep -v target | sort)
      ;;
    dotnet)
      while IFS= read -r f; do files+=("$f"); done < <(find "$root" \( -name "*.csproj" -o -name "*.sln" -o -name "Directory.Build.props" -o -name "Directory.Packages.props" \) -not -path "*/bin/*" -not -path "*/obj/*" -not -path "*/.git/*" 2>/dev/null | sort)
      ;;
  esac

  if [[ ${#files[@]} -eq 0 ]]; then
    echo ""
    return
  fi

  # Compute composite hash of all build files
  local hash_input=""
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      local rel_path="${f#"$root"/}"
      local file_hash
      file_hash="$(shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1)"
      hash_input+="${rel_path}:${file_hash};"
    fi
  done
  echo "$hash_input"
}

is_cache_valid() {
  local system="$1" cache_file="$2" project_root="$3"

  [[ -f "$cache_file" ]] || return 1
  [[ "$FORCE_REFRESH" == "true" ]] && return 1
  [[ "$CACHE_ENABLED" != "true" ]] && return 1

  local current_hashes stored_hashes
  current_hashes="$(compute_build_file_hashes "$system" "$project_root")"

  stored_hashes="$("${FORGE_PYTHON:-python3}" -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    entry = data.get('entries', {}).get(sys.argv[2], {})
    print(entry.get('build_file_hashes_composite', ''))
except Exception:
    print('')
" "$cache_file" "$system" 2>/dev/null || echo "")"

  [[ -n "$current_hashes" && "$current_hashes" == "$stored_hashes" ]]
}

write_cache_entry() {
  local system="$1" cache_file="$2" project_root="$3" resolution_mode="$4" deps_json="$5"

  local composite_hash
  composite_hash="$(compute_build_file_hashes "$system" "$project_root")"

  "${FORGE_PYTHON:-python3}" -c "
import json, sys, os
from datetime import datetime, timezone

cache_path = sys.argv[1]
system = sys.argv[2]
composite_hash = sys.argv[3]
resolution_mode = sys.argv[4]
deps_json = sys.argv[5]

data = {'version': '1.0.0', 'entries': {}}
if os.path.isfile(cache_path):
    try:
        with open(cache_path) as f:
            data = json.load(f)
    except Exception:
        pass

data['entries'][system] = {
    'build_file_hashes_composite': composite_hash,
    'introspected_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'resolution_mode': resolution_mode,
    'dependencies': json.loads(deps_json) if deps_json else []
}

with open(cache_path, 'w') as f:
    json.dump(data, f, indent=2)
" "$cache_file" "$system" "$composite_hash" "$resolution_mode" "$deps_json" 2>/dev/null || true
}

# -- Maven introspection -----------------------------------------------------

introspect_maven() {
  local project_root="$1"

  command -v mvn &>/dev/null || {
    echo "[build-resolver] INFO: mvn not found. Using heuristic fallback for Maven." >&2
    return 1
  }

  local tmpfile
  tmpfile="$(mktemp)"
  trap "rm -f '$tmpfile'" RETURN

  if ! portable_timeout "$INTROSPECTION_TIMEOUT" \
    mvn dependency:tree -DoutputType=text -DoutputFile="$tmpfile" -q -f "$project_root/pom.xml" 2>/dev/null; then
    echo "[build-resolver] WARNING: mvn dependency:tree failed or timed out." >&2
    return 1
  fi

  [[ -s "$tmpfile" ]] || {
    echo "[build-resolver] WARNING: mvn dependency:tree returned empty output." >&2
    return 1
  }

  "${FORGE_PYTHON:-python3}" -c "
import sys, json, re

deps = []
seen = set()
with open(sys.argv[1]) as f:
    for line in f:
        line = line.rstrip()
        # Match lines like: +- org.springframework:spring-context:jar:6.1.4:compile
        # or: |  +- org.slf4j:slf4j-api:jar:2.0.12:compile
        m = re.search(r'[\+\|\\\\]\-\s+(\S+):(\S+):(\S+):(\S+):(\S+)', line)
        if not m:
            # Root artifact line: com.example:parent:pom:1.0.0
            m = re.match(r'^(\S+):(\S+):(\S+):(\S+)$', line.strip())
            if m:
                continue  # Skip root artifact
            continue
        group_id = m.group(1)
        artifact_id = m.group(2)
        # packaging = m.group(3)
        version = m.group(4)
        scope = m.group(5)
        key = f'{group_id}:{artifact_id}'
        if key not in seen:
            seen.add(key)
            deps.append({
                'name': key,
                'version': version,
                'scope': scope,
                'source': 'maven',
                'confidence': 'introspected'
            })

json.dump(deps, sys.stdout, indent=2)
" "$tmpfile"
}

fallback_maven() {
  local project_root="$1"

  [[ -f "$project_root/pom.xml" ]] || {
    echo "[]"
    return 0
  }

  "${FORGE_PYTHON:-python3}" -c "
import xml.etree.ElementTree as ET
import json, sys, os

ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
root_dir = sys.argv[1]
pom_path = os.path.join(root_dir, 'pom.xml')

try:
    tree = ET.parse(pom_path)
except ET.ParseError:
    json.dump([], sys.stdout)
    sys.exit(0)

root = tree.getroot()

# Extract groupId (inherit from parent if needed)
parent = root.find('m:parent', ns)
group_id = root.findtext('m:groupId', namespaces=ns)
if not group_id and parent is not None:
    group_id = parent.findtext('m:groupId', namespaces=ns)

deps = []
seen = set()

for dep in root.findall('.//m:dependencies/m:dependency', ns):
    g = dep.findtext('m:groupId', namespaces=ns) or ''
    a = dep.findtext('m:artifactId', namespaces=ns) or ''
    v = dep.findtext('m:version', namespaces=ns) or 'managed'
    s = dep.findtext('m:scope', namespaces=ns) or 'compile'
    if not a:
        continue
    key = f'{g}:{a}'
    if key not in seen:
        seen.add(key)
        deps.append({
            'name': key,
            'version': v,
            'scope': s,
            'source': 'maven',
            'confidence': 'heuristic'
        })

json.dump(deps, sys.stdout, indent=2)
" "$project_root"
}

# -- Gradle introspection ----------------------------------------------------

introspect_gradle() {
  local project_root="$1"

  command -v gradle &>/dev/null || {
    echo "[build-resolver] INFO: gradle not found. Using heuristic fallback for Gradle." >&2
    return 1
  }

  local deps_output
  deps_output="$(cd "$project_root" && portable_timeout "$INTROSPECTION_TIMEOUT" \
    gradle dependencies --configuration runtimeClasspath -q 2>/dev/null)" || {
    echo "[build-resolver] WARNING: gradle dependencies failed or timed out." >&2
    return 1
  }

  [[ -n "$deps_output" ]] || {
    echo "[build-resolver] WARNING: gradle dependencies returned empty output." >&2
    return 1
  }

  echo "$deps_output" | "${FORGE_PYTHON:-python3}" -c "
import sys, json, re

deps = []
seen = set()
for line in sys.stdin:
    line = line.rstrip()
    # Match: +--- org.springframework:spring-context:6.1.4
    # or: |    +--- com.google.guava:guava:32.1.3-jre
    # or: \--- org.junit.jupiter:junit-jupiter:5.10.0
    # Handle version conflict arrows: 1.2.3 -> 1.3.0
    m = re.search(r'[+|\\\\]---\s+(\S+):(\S+):(\S+?)(?:\s*->.*)?(?:\s+\(.*\))?$', line)
    if not m:
        continue
    group_id = m.group(1)
    artifact_id = m.group(2)
    version = m.group(3)
    # Skip project references
    if group_id == 'project':
        continue
    key = f'{group_id}:{artifact_id}'
    if key not in seen:
        seen.add(key)
        deps.append({
            'name': key,
            'version': version,
            'scope': 'runtime',
            'source': 'gradle',
            'confidence': 'introspected'
        })

json.dump(deps, sys.stdout, indent=2)
"
}

fallback_gradle() {
  local project_root="$1"

  "${FORGE_PYTHON:-python3}" -c "
import re, json, sys, os

root = sys.argv[1]
deps = []
seen = set()

# Find all build.gradle(.kts) files
build_files = []
for dirpath, dirnames, filenames in os.walk(root):
    # Skip build directories
    dirnames[:] = [d for d in dirnames if d not in ('build', '.gradle', '.git', 'node_modules')]
    for fn in filenames:
        if fn in ('build.gradle', 'build.gradle.kts'):
            build_files.append(os.path.join(dirpath, fn))

for bf in build_files:
    with open(bf) as f:
        content = f.read()

    # Match patterns: implementation('group:artifact:version') or implementation(\"group:artifact:version\")
    # Also: api, testImplementation, runtimeOnly, compileOnly
    for m in re.finditer(
        r'(implementation|api|testImplementation|runtimeOnly|compileOnly)\s*[\(]?\s*[\"' + \"'\" + r']([^\"' + \"'\" + r']+)[\"' + \"'\" + r']',
        content
    ):
        config_name = m.group(1)
        dep_str = m.group(2)
        parts = dep_str.split(':')
        if len(parts) >= 2:
            group_id = parts[0]
            artifact_id = parts[1]
            version = parts[2] if len(parts) >= 3 else 'unspecified'
            key = f'{group_id}:{artifact_id}'
            if key not in seen:
                seen.add(key)
                scope = 'test' if 'test' in config_name.lower() else 'runtime'
                deps.append({
                    'name': key,
                    'version': version,
                    'scope': scope,
                    'source': 'gradle',
                    'confidence': 'heuristic'
                })

json.dump(deps, sys.stdout, indent=2)
" "$project_root"
}

# -- npm/pnpm/yarn introspection ---------------------------------------------

introspect_npm() {
  local project_root="$1"

  command -v npm &>/dev/null || {
    echo "[build-resolver] INFO: npm not found." >&2
    return 1
  }

  local output
  output="$(cd "$project_root" && portable_timeout "$INTROSPECTION_TIMEOUT" \
    npm ls --json --all --depth=1 2>/dev/null)" || {
    echo "[build-resolver] WARNING: npm ls failed or timed out." >&2
    return 1
  }

  [[ -n "$output" ]] || return 1

  echo "$output" | "${FORGE_PYTHON:-python3}" -c "
import json, sys

data = json.load(sys.stdin)
deps = []
seen = set()

def walk(node, scope='runtime'):
    for dep_key in ('dependencies', 'devDependencies'):
        s = 'test' if dep_key == 'devDependencies' else scope
        for name, info in (node.get(dep_key) or {}).items():
            if name not in seen:
                seen.add(name)
                version = info.get('version', 'unknown') if isinstance(info, dict) else str(info)
                deps.append({
                    'name': name,
                    'version': version,
                    'scope': s,
                    'source': 'npm',
                    'confidence': 'introspected'
                })

walk(data)
json.dump(deps, sys.stdout, indent=2)
"
}

introspect_pnpm() {
  local project_root="$1"

  command -v pnpm &>/dev/null || {
    echo "[build-resolver] INFO: pnpm not found." >&2
    return 1
  }

  local output
  output="$(cd "$project_root" && portable_timeout "$INTROSPECTION_TIMEOUT" \
    pnpm ls --json --depth=1 2>/dev/null)" || {
    echo "[build-resolver] WARNING: pnpm ls failed or timed out." >&2
    return 1
  }

  [[ -n "$output" ]] || return 1

  echo "$output" | "${FORGE_PYTHON:-python3}" -c "
import json, sys

raw = json.load(sys.stdin)
# pnpm ls --json returns an array
data_list = raw if isinstance(raw, list) else [raw]
deps = []
seen = set()

for data in data_list:
    for dep_key in ('dependencies', 'devDependencies'):
        for name, info in (data.get(dep_key) or {}).items():
            if name not in seen:
                seen.add(name)
                version = info.get('version', 'unknown') if isinstance(info, dict) else str(info)
                scope = 'test' if dep_key == 'devDependencies' else 'runtime'
                deps.append({
                    'name': name,
                    'version': version,
                    'scope': scope,
                    'source': 'pnpm',
                    'confidence': 'introspected'
                })

json.dump(deps, sys.stdout, indent=2)
"
}

introspect_yarn() {
  local project_root="$1"

  command -v yarn &>/dev/null || {
    echo "[build-resolver] INFO: yarn not found." >&2
    return 1
  }

  local output
  output="$(cd "$project_root" && portable_timeout "$INTROSPECTION_TIMEOUT" \
    yarn list --json --depth=1 2>/dev/null)" || {
    echo "[build-resolver] WARNING: yarn list failed or timed out." >&2
    return 1
  }

  [[ -n "$output" ]] || return 1

  echo "$output" | "${FORGE_PYTHON:-python3}" -c "
import json, sys

deps = []
seen = set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
    except json.JSONDecodeError:
        continue
    # yarn list --json outputs {type: 'tree', data: {trees: [...]}}
    trees = data.get('data', {}).get('trees', [])
    for tree in trees:
        full_name = tree.get('name', '')
        # Format: 'package@version'
        at_idx = full_name.rfind('@')
        if at_idx > 0:
            name = full_name[:at_idx]
            version = full_name[at_idx+1:]
        else:
            name = full_name
            version = 'unknown'
        if name and name not in seen:
            seen.add(name)
            deps.append({
                'name': name,
                'version': version,
                'scope': 'runtime',
                'source': 'yarn',
                'confidence': 'introspected'
            })

json.dump(deps, sys.stdout, indent=2)
"
}

fallback_npm() {
  local project_root="$1"

  "${FORGE_PYTHON:-python3}" -c "
import json, sys, os, glob as glob_mod

root = sys.argv[1]
deps = []
seen = set()

# Find all package.json files (excluding node_modules)
pkg_files = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d != 'node_modules' and d != '.git']
    if 'package.json' in filenames:
        pkg_files.append(os.path.join(dirpath, 'package.json'))

for pkg_path in pkg_files:
    try:
        with open(pkg_path) as f:
            pkg = json.load(f)
    except (json.JSONDecodeError, IOError):
        continue

    for dep_key in ('dependencies', 'devDependencies'):
        scope = 'test' if dep_key == 'devDependencies' else 'runtime'
        for name, version in (pkg.get(dep_key) or {}).items():
            if name not in seen:
                seen.add(name)
                deps.append({
                    'name': name,
                    'version': str(version),
                    'scope': scope,
                    'source': 'npm',
                    'confidence': 'heuristic'
                })

json.dump(deps, sys.stdout, indent=2)
" "$project_root"
}

# -- Go introspection --------------------------------------------------------

introspect_go() {
  local project_root="$1"

  command -v go &>/dev/null || {
    echo "[build-resolver] INFO: go not found." >&2
    return 1
  }

  local output
  output="$(cd "$project_root" && portable_timeout "$INTROSPECTION_TIMEOUT" \
    go list -m all 2>/dev/null)" || {
    echo "[build-resolver] WARNING: go list -m all failed or timed out." >&2
    return 1
  }

  [[ -n "$output" ]] || return 1

  echo "$output" | "${FORGE_PYTHON:-python3}" -c "
import json, sys

deps = []
seen = set()
first = True
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    if first:
        # First line is the root module (skip it)
        first = False
        continue
    parts = line.split()
    name = parts[0]
    version = parts[1] if len(parts) >= 2 else 'unknown'
    if name not in seen:
        seen.add(name)
        deps.append({
            'name': name,
            'version': version,
            'scope': 'runtime',
            'source': 'go',
            'confidence': 'introspected'
        })

json.dump(deps, sys.stdout, indent=2)
"
}

fallback_go() {
  local project_root="$1"

  [[ -f "$project_root/go.mod" ]] || {
    echo "[]"
    return 0
  }

  "${FORGE_PYTHON:-python3}" -c "
import json, sys, re

mod_path = sys.argv[1] + '/go.mod'
with open(mod_path) as f:
    content = f.read()

deps = []
seen = set()
in_require = False

for line in content.splitlines():
    stripped = line.strip()

    if stripped.startswith('require ('):
        in_require = True
        continue
    if in_require and stripped == ')':
        in_require = False
        continue

    dep_line = None
    if in_require:
        dep_line = stripped
    elif stripped.startswith('require '):
        dep_line = stripped[len('require '):]

    if dep_line:
        # Remove inline comments
        dep_line = dep_line.split('//')[0].strip()
        parts = dep_line.split()
        if len(parts) >= 2:
            name = parts[0]
            version = parts[1]
            if name not in seen:
                seen.add(name)
                deps.append({
                    'name': name,
                    'version': version,
                    'scope': 'runtime',
                    'source': 'go',
                    'confidence': 'heuristic'
                })

json.dump(deps, sys.stdout, indent=2)
" "$project_root"
}

# -- Cargo introspection -----------------------------------------------------

introspect_cargo() {
  local project_root="$1"

  command -v cargo &>/dev/null || {
    echo "[build-resolver] INFO: cargo not found." >&2
    return 1
  }

  local metadata
  metadata="$(cd "$project_root" && portable_timeout "$INTROSPECTION_TIMEOUT" \
    cargo metadata --format-version 1 --no-deps 2>/dev/null)" || {
    echo "[build-resolver] WARNING: cargo metadata failed or timed out." >&2
    return 1
  }

  [[ -n "$metadata" ]] || return 1

  echo "$metadata" | "${FORGE_PYTHON:-python3}" -c "
import json, sys

data = json.load(sys.stdin)
deps = []
seen = set()

for pkg in data.get('packages', []):
    for dep in pkg.get('dependencies', []):
        name = dep.get('name', '')
        # Skip path dependencies (workspace members)
        if dep.get('path'):
            continue
        req = dep.get('req', 'unknown')
        kind = dep.get('kind') or 'normal'
        scope = 'test' if kind == 'dev' else 'runtime'
        if name and name not in seen:
            seen.add(name)
            deps.append({
                'name': name,
                'version': req,
                'scope': scope,
                'source': 'cargo',
                'confidence': 'introspected'
            })

json.dump(deps, sys.stdout, indent=2)
"
}

fallback_cargo() {
  local project_root="$1"

  [[ -f "$project_root/Cargo.toml" ]] || {
    echo "[]"
    return 0
  }

  "${FORGE_PYTHON:-python3}" -c "
import sys, json, os

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        json.dump([], sys.stdout)
        sys.exit(0)

root = sys.argv[1]
toml_path = os.path.join(root, 'Cargo.toml')

with open(toml_path, 'rb') as f:
    data = tomllib.load(f)

deps = []
seen = set()

for section_name in ('dependencies', 'dev-dependencies', 'build-dependencies'):
    scope = 'test' if section_name == 'dev-dependencies' else 'runtime'
    section = data.get(section_name, {})
    for name, val in section.items():
        if name in seen:
            continue
        seen.add(name)
        if isinstance(val, str):
            version = val
        elif isinstance(val, dict):
            version = val.get('version', 'path' if val.get('path') else 'unknown')
        else:
            version = 'unknown'
        deps.append({
            'name': name,
            'version': version,
            'scope': scope,
            'source': 'cargo',
            'confidence': 'heuristic'
        })

json.dump(deps, sys.stdout, indent=2)
" "$project_root"
}

# -- .NET introspection ------------------------------------------------------

introspect_dotnet() {
  local project_root="$1"

  command -v dotnet &>/dev/null || {
    echo "[build-resolver] INFO: dotnet not found." >&2
    return 1
  }

  local output
  output="$(cd "$project_root" && portable_timeout "$INTROSPECTION_TIMEOUT" \
    dotnet list package --format json 2>/dev/null)" || {
    # --format json requires .NET SDK 8+; fallback to text
    output="$(cd "$project_root" && portable_timeout "$INTROSPECTION_TIMEOUT" \
      dotnet list package 2>/dev/null)" || {
      echo "[build-resolver] WARNING: dotnet list package failed." >&2
      return 1
    }
  }

  [[ -n "$output" ]] || return 1

  echo "$output" | "${FORGE_PYTHON:-python3}" -c "
import json, sys, re

raw = sys.stdin.read()
deps = []
seen = set()

# Try JSON first
try:
    data = json.loads(raw)
    for proj in data.get('projects', []):
        for fw in proj.get('frameworks', []):
            for pkg in fw.get('topLevelPackages', []):
                name = pkg.get('id', '')
                version = pkg.get('resolvedVersion', pkg.get('requestedVersion', 'unknown'))
                if name and name not in seen:
                    seen.add(name)
                    deps.append({
                        'name': name,
                        'version': version,
                        'scope': 'runtime',
                        'source': 'dotnet',
                        'confidence': 'introspected'
                    })
    json.dump(deps, sys.stdout, indent=2)
    sys.exit(0)
except json.JSONDecodeError:
    pass

# Text format fallback: lines like '   > PackageName    1.2.3    1.2.3'
for line in raw.splitlines():
    m = re.match(r'\s+>\s+(\S+)\s+(\S+)\s+(\S+)', line)
    if m:
        name = m.group(1)
        version = m.group(3)  # resolved version
        if name and name not in seen:
            seen.add(name)
            deps.append({
                'name': name,
                'version': version,
                'scope': 'runtime',
                'source': 'dotnet',
                'confidence': 'introspected'
            })

json.dump(deps, sys.stdout, indent=2)
"
}

fallback_dotnet() {
  local project_root="$1"

  "${FORGE_PYTHON:-python3}" -c "
import xml.etree.ElementTree as ET
import json, sys, os

root_dir = sys.argv[1]
deps = []
seen = set()

# Find all .csproj files
for dirpath, dirnames, filenames in os.walk(root_dir):
    dirnames[:] = [d for d in dirnames if d not in ('bin', 'obj', '.git', 'node_modules')]
    for fn in filenames:
        if fn.endswith('.csproj'):
            csproj = os.path.join(dirpath, fn)
            try:
                tree = ET.parse(csproj)
                for ref in tree.findall('.//PackageReference'):
                    name = ref.get('Include', '')
                    version = ref.get('Version', 'unspecified')
                    if name and name not in seen:
                        seen.add(name)
                        deps.append({
                            'name': name,
                            'version': version,
                            'scope': 'runtime',
                            'source': 'dotnet',
                            'confidence': 'heuristic'
                        })
            except ET.ParseError:
                pass

json.dump(deps, sys.stdout, indent=2)
" "$project_root"
}

# -- Resolve a single build system ------------------------------------------

resolve_system() {
  local system="$1" project_root="$2"

  # Check cache first
  if is_cache_valid "$system" "$CACHE_FILE" "$project_root"; then
    echo "[build-resolver] Cache hit for $system." >&2
    "${FORGE_PYTHON:-python3}" -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
entry = data['entries'][sys.argv[2]]
json.dump(entry.get('dependencies', []), sys.stdout, indent=2)
" "$CACHE_FILE" "$system" 2>/dev/null
    # Echo the cached resolution mode to fd 3 so the caller can capture it
    echo "cached" >&3
    return 0
  fi

  echo "[build-resolver] Introspecting $system..." >&2

  local deps_json=""
  local resolution_mode="heuristic"

  # Try introspection first
  case "$system" in
    maven)  deps_json="$(introspect_maven "$project_root")" && resolution_mode="introspected" ;;
    gradle) deps_json="$(introspect_gradle "$project_root")" && resolution_mode="introspected" ;;
    npm)    deps_json="$(introspect_npm "$project_root")" && resolution_mode="introspected" ;;
    pnpm)   deps_json="$(introspect_pnpm "$project_root")" && resolution_mode="introspected" ;;
    yarn)   deps_json="$(introspect_yarn "$project_root")" && resolution_mode="introspected" ;;
    go)     deps_json="$(introspect_go "$project_root")" && resolution_mode="introspected" ;;
    cargo)  deps_json="$(introspect_cargo "$project_root")" && resolution_mode="introspected" ;;
    dotnet) deps_json="$(introspect_dotnet "$project_root")" && resolution_mode="introspected" ;;
  esac

  # Fallback if introspection failed
  if [[ -z "$deps_json" || "$deps_json" == "[]" ]]; then
    if [[ "$FALLBACK_MODE" == "skip" ]]; then
      echo "[build-resolver] Introspection failed for $system. Skipping (fallback=skip)." >&2
      echo "[]"
      echo "skipped" >&3
      return 0
    fi

    echo "[build-resolver] Introspection failed for $system. Using heuristic fallback." >&2
    resolution_mode="heuristic"
    case "$system" in
      maven)  deps_json="$(fallback_maven "$project_root")" ;;
      gradle) deps_json="$(fallback_gradle "$project_root")" ;;
      npm|pnpm|yarn) deps_json="$(fallback_npm "$project_root")" ;;
      go)     deps_json="$(fallback_go "$project_root")" ;;
      cargo)  deps_json="$(fallback_cargo "$project_root")" ;;
      dotnet) deps_json="$(fallback_dotnet "$project_root")" ;;
    esac
    deps_json="${deps_json:-[]}"
  fi

  # Write to cache
  write_cache_entry "$system" "$CACHE_FILE" "$project_root" "$resolution_mode" "$deps_json"

  # Echo deps to stdout and resolution mode to fd 3
  echo "$deps_json"
  echo "$resolution_mode" >&3
}

# -- Main --------------------------------------------------------------------

main() {
  parse_args "$@"
  read_config

  # Check if introspection is disabled
  if [[ "${INTROSPECTION_ENABLED:-true}" == "false" ]]; then
    echo "[build-resolver] Introspection disabled via config." >&2
    echo '{"build_systems":[],"dependencies":[],"resolution_mode":"heuristic"}'
    exit 0
  fi

  FORGE_DIR="${PROJECT_ROOT}/.forge"
  mkdir -p "$FORGE_DIR"
  CACHE_FILE="${FORGE_DIR}/build-graph-cache.json"

  local -a systems=()
  while IFS= read -r sys; do
    [[ -z "$sys" ]] && continue
    systems+=("$sys")
  done < <(detect_build_systems "$PROJECT_ROOT")

  if [[ ${#systems[@]} -eq 0 ]]; then
    echo "[build-resolver] No build systems detected." >&2
    echo '{"build_systems":[],"dependencies":[],"resolution_mode":"heuristic"}'
    exit 0
  fi

  echo "[build-resolver] Detected build systems: ${systems[*]}" >&2

  # Resolve each system and merge results.
  # resolve_system() writes deps JSON to stdout and resolution mode to fd 3.
  # We capture the mode via a temp file on fd 3.
  local all_deps="[]"
  local resolution_modes=()
  local mode_file
  mode_file="$(mktemp)"

  for sys in "${systems[@]}"; do
    local sys_deps mode
    # Open fd 3 pointing to mode_file; resolve_system writes mode there
    sys_deps="$(resolve_system "$sys" "$PROJECT_ROOT" 3>"$mode_file")" || true
    mode="$(cat "$mode_file" 2>/dev/null)"
    [[ -n "$mode" ]] && resolution_modes+=("$mode")
    : > "$mode_file"  # reset for next iteration

    if [[ -n "$sys_deps" && "$sys_deps" != "[]" ]]; then
      all_deps="$("${FORGE_PYTHON:-python3}" -c "
import json, sys
a = json.loads(sys.argv[1])
b = json.loads(sys.argv[2])
json.dump(a + b, sys.stdout)
" "$all_deps" "$sys_deps" 2>/dev/null || echo "$all_deps")"
    fi
  done
  rm -f "$mode_file"

  # Determine overall resolution mode
  local overall_mode="heuristic"
  if [[ ${#resolution_modes[@]} -gt 0 ]]; then
    local has_introspected=false has_heuristic=false
    for m in "${resolution_modes[@]}"; do
      [[ "$m" == "introspected" ]] && has_introspected=true
      [[ "$m" == "heuristic" ]] && has_heuristic=true
    done
    if [[ "$has_introspected" == "true" && "$has_heuristic" == "true" ]]; then
      overall_mode="mixed"
    elif [[ "$has_introspected" == "true" ]]; then
      overall_mode="introspected"
    fi
  fi

  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    "${FORGE_PYTHON:-python3}" -c "
import json, sys

result = {
    'build_systems': json.loads(sys.argv[1]),
    'dependencies': json.loads(sys.argv[2]),
    'resolution_mode': sys.argv[3]
}
json.dump(result, sys.stdout, indent=2)
" "$(printf '%s\n' "${systems[@]}" | "${FORGE_PYTHON:-python3}" -c "import json,sys; json.dump([l.strip() for l in sys.stdin if l.strip()], sys.stdout)")" \
  "$all_deps" "$overall_mode"
  fi
}

if [[ "$_SOURCE_ONLY" != "true" ]]; then
  main "$@"
fi
