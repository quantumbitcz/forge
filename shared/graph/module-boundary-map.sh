#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# module-boundary-map.sh -- Module Boundary Discovery
#
# Discovers all modules/subprojects/crates/workspaces in the project and maps
# each to its source directories, test directories, and artifact coordinates.
#
# Usage:
#   ./shared/graph/module-boundary-map.sh \
#       --project-root /path/to/project \
#       [--build-system maven|gradle|cargo|go|npm|dotnet|auto] \
#       [--output /path/to/output.json]
#
# Output: JSON to stdout (or to --output file)
# Exit 0 on success, 0 on graceful degradation
# ============================================================================

# Support --source-only for unit testing
if [[ "${1:-}" == "--source-only" ]]; then
  _SOURCE_ONLY=true
  shift
else
  _SOURCE_ONLY=false
fi

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../platform.sh
source "${PLUGIN_ROOT}/shared/platform.sh"

require_bash4 "module-boundary-map.sh" || exit 1

# -- Defaults ----------------------------------------------------------------

PROJECT_ROOT=""
BUILD_SYSTEM="auto"
OUTPUT_FILE=""
INTROSPECTION_TIMEOUT=60

# -- Argument parsing --------------------------------------------------------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root)   PROJECT_ROOT="$2"; shift 2 ;;
      --build-system)   BUILD_SYSTEM="$2"; shift 2 ;;
      --output)         OUTPUT_FILE="$2"; shift 2 ;;
      --timeout)        INTROSPECTION_TIMEOUT="$2"; shift 2 ;;
      *)
        echo "Error: Unknown argument: $1" >&2
        echo "Usage: module-boundary-map.sh --project-root /path [--build-system auto] [--output file.json]" >&2
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

# -- Maven module discovery --------------------------------------------------

discover_maven_modules() {
  local root="$1"

  [[ -f "$root/pom.xml" ]] || {
    echo '{"build_system":"maven","root":"'"$root"'","modules":[]}'
    return 0
  }

  "${FORGE_PYTHON:-python3}" << 'PYEOF' - "$root"
import xml.etree.ElementTree as ET
import os, sys, json

root_dir = sys.argv[1]
ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
result = {"build_system": "maven", "root": root_dir, "modules": []}

def parse_pom(pom_path, parent_dir):
    try:
        tree = ET.parse(pom_path)
        root = tree.getroot()
    except ET.ParseError:
        return None

    group_id = root.findtext('m:groupId', namespaces=ns)
    artifact_id = root.findtext('m:artifactId', namespaces=ns)

    parent = root.find('m:parent', ns)
    if not group_id and parent is not None:
        group_id = parent.findtext('m:groupId', namespaces=ns)

    if not artifact_id:
        return None

    module_dir = os.path.dirname(pom_path)
    rel_dir = os.path.relpath(module_dir, root_dir)
    if rel_dir == '.':
        rel_dir = ''

    source_dirs = []
    test_dirs = []
    for src_type in ['java', 'kotlin', 'scala', 'groovy']:
        src_path = os.path.join(rel_dir, 'src', 'main', src_type) if rel_dir else os.path.join('src', 'main', src_type)
        if os.path.isdir(os.path.join(root_dir, src_path)):
            source_dirs.append(src_path)
        test_path = os.path.join(rel_dir, 'src', 'test', src_type) if rel_dir else os.path.join('src', 'test', src_type)
        if os.path.isdir(os.path.join(root_dir, test_path)):
            test_dirs.append(test_path)

    depends_on = []
    for dep in root.findall('.//m:dependencies/m:dependency', ns):
        dep_group = dep.findtext('m:groupId', namespaces=ns) or ''
        dep_artifact = dep.findtext('m:artifactId', namespaces=ns) or ''
        if dep_group and dep_artifact:
            depends_on.append(f"{dep_group}:{dep_artifact}")

    return {
        "name": artifact_id,
        "artifact_id": f"{group_id}:{artifact_id}" if group_id else artifact_id,
        "directory": rel_dir or ".",
        "source_dirs": source_dirs,
        "test_dirs": test_dirs,
        "depends_on_artifacts": depends_on
    }

def walk_modules(pom_path):
    try:
        tree = ET.parse(pom_path)
        root_el = tree.getroot()
    except ET.ParseError:
        return

    module_info = parse_pom(pom_path, os.path.dirname(pom_path))
    if module_info:
        result["modules"].append(module_info)

    modules_el = root_el.find('m:modules', ns)
    if modules_el is not None:
        for mod in modules_el.findall('m:module', ns):
            child_dir = mod.text.strip() if mod.text else None
            if child_dir:
                child_pom = os.path.join(os.path.dirname(pom_path), child_dir, 'pom.xml')
                if os.path.isfile(child_pom):
                    walk_modules(child_pom)

walk_modules(os.path.join(root_dir, 'pom.xml'))

# Resolve inter-module depends_on
artifact_to_name = {m["artifact_id"]: m["name"] for m in result["modules"]}
for mod in result["modules"]:
    resolved = []
    for dep_artifact in mod.pop("depends_on_artifacts", []):
        if dep_artifact in artifact_to_name:
            resolved.append(artifact_to_name[dep_artifact])
    mod["depends_on"] = resolved

# Compute depended_by
for mod in result["modules"]:
    mod["depended_by"] = [
        m["name"] for m in result["modules"]
        if mod["name"] in m.get("depends_on", [])
    ]

json.dump(result, sys.stdout, indent=2)
PYEOF
}

# -- Gradle module discovery -------------------------------------------------

discover_gradle_modules() {
  local root="$1"

  # Strategy 1: Use gradle projects -q if available
  if command -v gradle &>/dev/null; then
    local projects_output
    projects_output="$(cd "$root" && portable_timeout "$INTROSPECTION_TIMEOUT" gradle projects -q 2>/dev/null)" || true
    if [[ -n "$projects_output" ]]; then
      echo "$projects_output" | "${FORGE_PYTHON:-python3}" << 'PYEOF' - "$root"
import re, os, sys, json

root_dir = sys.argv[1]
result = {"build_system": "gradle", "root": root_dir, "modules": []}

modules = []
for line in sys.stdin:
    m = re.search(r"Project\s+':([\w\-]+)'", line)
    if m:
        modules.append(m.group(1))

for mod_name in modules:
    mod_dir = mod_name
    source_dirs = []
    test_dirs = []
    for lang in ['java', 'kotlin', 'scala', 'groovy']:
        src = os.path.join(mod_dir, 'src', 'main', lang)
        if os.path.isdir(os.path.join(root_dir, src)):
            source_dirs.append(src)
        tst = os.path.join(mod_dir, 'src', 'test', lang)
        if os.path.isdir(os.path.join(root_dir, tst)):
            test_dirs.append(tst)

    depends_on = []
    for bf in ['build.gradle.kts', 'build.gradle']:
        build_file = os.path.join(root_dir, mod_dir, bf)
        if os.path.isfile(build_file):
            with open(build_file) as f:
                content = f.read()
            for dep_m in re.finditer(r"project\s*\(\s*[\"']:([^\"']+)", content):
                dep = dep_m.group(1).strip(':')
                if dep != mod_name:
                    depends_on.append(dep)
            break

    result["modules"].append({
        "name": mod_name, "artifact_id": mod_name, "directory": mod_dir,
        "source_dirs": source_dirs, "test_dirs": test_dirs,
        "depends_on": list(dict.fromkeys(depends_on))
    })

for mod in result["modules"]:
    mod["depended_by"] = [m["name"] for m in result["modules"] if mod["name"] in m.get("depends_on", [])]

json.dump(result, sys.stdout, indent=2)
PYEOF
      return $?
    fi
  fi

  # Strategy 2: Parse settings.gradle(.kts) directly
  local settings_file=""
  [[ -f "$root/settings.gradle.kts" ]] && settings_file="$root/settings.gradle.kts"
  [[ -f "$root/settings.gradle" ]] && settings_file="$root/settings.gradle"
  if [[ -z "$settings_file" ]]; then
    # Single-module Gradle project
    "${FORGE_PYTHON:-python3}" -c "
import os, sys, json
root_dir = sys.argv[1]
result = {'build_system': 'gradle', 'root': root_dir, 'modules': []}
for lang_dir in ['java', 'kotlin', 'scala', 'groovy']:
    src = os.path.join('src', 'main', lang_dir)
    if os.path.isdir(os.path.join(root_dir, src)):
        result['modules'].append({
            'name': '__root__', 'artifact_id': '__root__', 'directory': '.',
            'source_dirs': [src], 'test_dirs': [], 'depends_on': [], 'depended_by': []
        })
        break
if not result['modules']:
    result['modules'].append({
        'name': '__root__', 'artifact_id': '__root__', 'directory': '.',
        'source_dirs': [], 'test_dirs': [], 'depends_on': [], 'depended_by': []
    })
json.dump(result, sys.stdout, indent=2)
" "$root"
    return $?
  fi

  "${FORGE_PYTHON:-python3}" << 'PYEOF' - "$settings_file" "$root"
import re, os, sys, json

settings_path = sys.argv[1]
root_dir = sys.argv[2]

with open(settings_path, 'r') as f:
    content = f.read()

modules = []
for m in re.finditer(r'include\s*\(?\s*["\']?:?([^"\')\s,]+)', content):
    name = m.group(1).strip(":'\"")
    modules.append(name)

modules = list(dict.fromkeys(modules))

result = {"build_system": "gradle", "root": root_dir, "modules": []}

for mod_name in modules:
    mod_dir = mod_name.replace(':', '/')
    source_dirs = []
    test_dirs = []
    for lang_dir in ['java', 'kotlin', 'scala', 'groovy']:
        src = os.path.join(mod_dir, 'src', 'main', lang_dir)
        if os.path.isdir(os.path.join(root_dir, src)):
            source_dirs.append(src)
        tst = os.path.join(mod_dir, 'src', 'test', lang_dir)
        if os.path.isdir(os.path.join(root_dir, tst)):
            test_dirs.append(tst)

    depends_on = []
    for build_file_name in ['build.gradle.kts', 'build.gradle']:
        build_file = os.path.join(root_dir, mod_dir, build_file_name)
        if os.path.isfile(build_file):
            with open(build_file, 'r') as f:
                build_content = f.read()
            for dep_match in re.finditer(r'project\s*\(\s*["\']:([^"\']+)', build_content):
                dep_name = dep_match.group(1).strip(':')
                if dep_name != mod_name:
                    depends_on.append(dep_name)
            break

    result["modules"].append({
        "name": mod_name, "artifact_id": mod_name, "directory": mod_dir,
        "source_dirs": source_dirs, "test_dirs": test_dirs,
        "depends_on": list(dict.fromkeys(depends_on))
    })

# Add root project if it has source dirs
for lang_dir in ['java', 'kotlin', 'scala', 'groovy']:
    root_src = os.path.join('src', 'main', lang_dir)
    if os.path.isdir(os.path.join(root_dir, root_src)):
        result["modules"].insert(0, {
            "name": "__root__", "artifact_id": "__root__", "directory": ".",
            "source_dirs": [root_src], "test_dirs": [], "depends_on": []
        })
        break

for mod in result["modules"]:
    mod["depended_by"] = [m["name"] for m in result["modules"] if mod["name"] in m.get("depends_on", [])]

json.dump(result, sys.stdout, indent=2)
PYEOF
}

# -- Cargo workspace discovery -----------------------------------------------

discover_cargo_modules() {
  local root="$1"

  # Strategy 1: cargo metadata (preferred)
  if command -v cargo &>/dev/null; then
    local metadata
    metadata="$(cd "$root" && portable_timeout "$INTROSPECTION_TIMEOUT" \
      cargo metadata --format-version 1 --no-deps 2>/dev/null)" || true
    if [[ -n "$metadata" ]]; then
      echo "$metadata" | "${FORGE_PYTHON:-python3}" << 'PYEOF'
import json, sys, os

data = json.load(sys.stdin)
workspace_root = data.get("workspace_root", "")
result = {"build_system": "cargo", "root": workspace_root, "modules": []}

for pkg in data.get("packages", []):
    manifest = pkg.get("manifest_path", "")
    pkg_dir = os.path.dirname(manifest)
    rel_dir = os.path.relpath(pkg_dir, workspace_root) if workspace_root else pkg_dir

    src_dir = os.path.join(rel_dir, "src")
    source_dirs = [src_dir] if os.path.isdir(os.path.join(workspace_root, src_dir)) else []
    test_dir = os.path.join(rel_dir, "tests")
    test_dirs = [test_dir] if os.path.isdir(os.path.join(workspace_root, test_dir)) else []

    depends_on = []
    for dep in pkg.get("dependencies", []):
        if dep.get("path"):
            depends_on.append(dep["name"])

    result["modules"].append({
        "name": pkg["name"], "artifact_id": pkg["name"], "directory": rel_dir,
        "source_dirs": source_dirs, "test_dirs": test_dirs,
        "depends_on": depends_on
    })

for mod in result["modules"]:
    mod["depended_by"] = [m["name"] for m in result["modules"] if mod["name"] in m.get("depends_on", [])]

json.dump(result, sys.stdout, indent=2)
PYEOF
      return $?
    fi
  fi

  # Strategy 2: Parse Cargo.toml directly
  "${FORGE_PYTHON:-python3}" << 'PYEOF' - "$root"
import sys, os, json
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        json.dump({"build_system": "cargo", "root": sys.argv[1], "modules": []}, sys.stdout, indent=2)
        sys.exit(0)

root_dir = sys.argv[1]
result = {"build_system": "cargo", "root": root_dir, "modules": []}

with open(os.path.join(root_dir, "Cargo.toml"), "rb") as f:
    root_toml = tomllib.load(f)

workspace = root_toml.get("workspace", {})
members = workspace.get("members", [])

if not members:
    name = root_toml.get("package", {}).get("name", "root")
    result["modules"].append({
        "name": name, "artifact_id": name, "directory": ".",
        "source_dirs": ["src"] if os.path.isdir(os.path.join(root_dir, "src")) else [],
        "test_dirs": ["tests"] if os.path.isdir(os.path.join(root_dir, "tests")) else [],
        "depends_on": [], "depended_by": []
    })
else:
    import glob
    expanded = []
    for pattern in members:
        matched = glob.glob(os.path.join(root_dir, pattern))
        for m in matched:
            if os.path.isfile(os.path.join(m, "Cargo.toml")):
                expanded.append(os.path.relpath(m, root_dir))

    for member_dir in expanded:
        toml_path = os.path.join(root_dir, member_dir, "Cargo.toml")
        if not os.path.isfile(toml_path):
            continue
        with open(toml_path, "rb") as f:
            member_toml = tomllib.load(f)
        name = member_toml.get("package", {}).get("name", os.path.basename(member_dir))
        depends_on = []
        for dep_name, dep_val in member_toml.get("dependencies", {}).items():
            if isinstance(dep_val, dict) and dep_val.get("path"):
                depends_on.append(dep_name)
        result["modules"].append({
            "name": name, "artifact_id": name, "directory": member_dir,
            "source_dirs": [os.path.join(member_dir, "src")],
            "test_dirs": [os.path.join(member_dir, "tests")] if os.path.isdir(os.path.join(root_dir, member_dir, "tests")) else [],
            "depends_on": depends_on
        })

    for mod in result["modules"]:
        mod["depended_by"] = [m["name"] for m in result["modules"] if mod["name"] in m.get("depends_on", [])]

json.dump(result, sys.stdout, indent=2)
PYEOF
}

# -- Go workspace/module discovery -------------------------------------------

discover_go_modules() {
  local root="$1"

  "${FORGE_PYTHON:-python3}" << 'PYEOF' - "$root"
import os, sys, json, re

root_dir = sys.argv[1]
result = {"build_system": "go", "root": root_dir, "modules": []}

def parse_go_mod(mod_path):
    with open(mod_path, 'r') as f:
        content = f.read()

    mod_match = re.search(r'^module\s+(\S+)', content, re.MULTILINE)
    module_name = mod_match.group(1) if mod_match else ""

    requires = []
    in_require = False
    for line in content.splitlines():
        line = line.strip()
        if line.startswith('require ('):
            in_require = True
            continue
        if in_require and line == ')':
            in_require = False
            continue
        if in_require:
            parts = line.split()
            if len(parts) >= 1:
                requires.append(parts[0])
        elif line.startswith('require '):
            parts = line.split()
            if len(parts) >= 2:
                requires.append(parts[1])

    replaces = {}
    in_replace = False
    for line in content.splitlines():
        line = line.strip()
        if line.startswith('replace ('):
            in_replace = True
            continue
        if in_replace and line == ')':
            in_replace = False
            continue
        replace_line = line if in_replace else (line[len('replace '):] if line.startswith('replace ') else None)
        if replace_line:
            parts = replace_line.split('=>')
            if len(parts) == 2:
                original = parts[0].strip().split()[0]
                replacement = parts[1].strip().split()[0]
                if replacement.startswith('.') or replacement.startswith('/'):
                    replaces[original] = replacement

    return module_name, requires, replaces

go_work = os.path.join(root_dir, "go.work")
if os.path.isfile(go_work):
    with open(go_work, 'r') as f:
        work_content = f.read()
    use_dirs = []
    in_use = False
    for line in work_content.splitlines():
        line = line.strip()
        if line.startswith('use ('):
            in_use = True
            continue
        if in_use and line == ')':
            in_use = False
            continue
        if in_use:
            use_dirs.append(line.strip())
        elif line.startswith('use '):
            use_dirs.append(line[4:].strip())

    modules_by_name = {}
    for use_dir in use_dirs:
        mod_file = os.path.join(root_dir, use_dir, "go.mod")
        if os.path.isfile(mod_file):
            mod_name, requires, replaces = parse_go_mod(mod_file)
            modules_by_name[mod_name] = {
                "name": os.path.basename(use_dir),
                "artifact_id": mod_name,
                "directory": use_dir,
                "source_dirs": [use_dir],
                "test_dirs": [use_dir],
                "depends_on": [],
                "_requires": requires,
                "_replaces": replaces
            }

    all_module_names = set(modules_by_name.keys())
    for mod_name, info in modules_by_name.items():
        for req in info.pop("_requires", []):
            if req in all_module_names:
                info["depends_on"].append(modules_by_name[req]["name"])
        for original, local_path in info.pop("_replaces", {}).items():
            if original in all_module_names:
                info["depends_on"].append(modules_by_name[original]["name"])
        result["modules"].append(info)
else:
    mod_file = os.path.join(root_dir, "go.mod")
    if os.path.isfile(mod_file):
        mod_name, requires, replaces = parse_go_mod(mod_file)
        result["modules"].append({
            "name": os.path.basename(root_dir),
            "artifact_id": mod_name,
            "directory": ".",
            "source_dirs": ["."],
            "test_dirs": ["."],
            "depends_on": []
        })

for mod in result["modules"]:
    mod["depended_by"] = [m["name"] for m in result["modules"] if mod["name"] in m.get("depends_on", [])]

json.dump(result, sys.stdout, indent=2)
PYEOF
}

# -- npm/yarn workspace discovery --------------------------------------------

discover_js_modules() {
  local root="$1"

  "${FORGE_PYTHON:-python3}" << 'PYEOF' - "$root"
import os, sys, json, glob as glob_mod

root_dir = sys.argv[1]
result = {"build_system": "npm", "root": root_dir, "modules": []}

pkg_path = os.path.join(root_dir, "package.json")
if not os.path.isfile(pkg_path):
    json.dump(result, sys.stdout, indent=2)
    sys.exit(0)

with open(pkg_path) as f:
    root_pkg = json.load(f)

# Detect package manager
if os.path.isfile(os.path.join(root_dir, "pnpm-workspace.yaml")):
    result["build_system"] = "pnpm"
    import re
    with open(os.path.join(root_dir, "pnpm-workspace.yaml")) as f:
        content = f.read()
    workspace_patterns = re.findall(r"- ['\"]?([^'\"\n]+)", content)
elif os.path.isfile(os.path.join(root_dir, "yarn.lock")):
    result["build_system"] = "yarn"
    workspace_patterns = root_pkg.get("workspaces", [])
    if isinstance(workspace_patterns, dict):
        workspace_patterns = workspace_patterns.get("packages", [])
else:
    result["build_system"] = "npm"
    workspace_patterns = root_pkg.get("workspaces", [])

if not workspace_patterns:
    name = root_pkg.get("name", "root")
    source_dirs = []
    for d in ["src", "lib", "app"]:
        if os.path.isdir(os.path.join(root_dir, d)):
            source_dirs.append(d)
    test_dirs = []
    for d in ["test", "tests", "__tests__", "spec"]:
        if os.path.isdir(os.path.join(root_dir, d)):
            test_dirs.append(d)
    result["modules"].append({
        "name": name, "artifact_id": name, "directory": ".",
        "source_dirs": source_dirs or ["."], "test_dirs": test_dirs,
        "depends_on": [], "depended_by": []
    })
    json.dump(result, sys.stdout, indent=2)
    sys.exit(0)

workspace_dirs = []
for pattern in workspace_patterns:
    matches = glob_mod.glob(os.path.join(root_dir, pattern))
    for match in matches:
        if os.path.isfile(os.path.join(match, "package.json")):
            workspace_dirs.append(os.path.relpath(match, root_dir))

name_to_dir = {}
pkg_data = {}
for ws_dir in workspace_dirs:
    ws_pkg_path = os.path.join(root_dir, ws_dir, "package.json")
    with open(ws_pkg_path) as f:
        ws_pkg = json.load(f)
    name = ws_pkg.get("name", os.path.basename(ws_dir))
    name_to_dir[name] = ws_dir
    pkg_data[name] = ws_pkg

all_workspace_names = set(name_to_dir.keys())
for name, ws_pkg in pkg_data.items():
    ws_dir = name_to_dir[name]
    all_deps = {}
    all_deps.update(ws_pkg.get("dependencies", {}))
    all_deps.update(ws_pkg.get("devDependencies", {}))
    cross_deps = [dep for dep in all_deps if dep in all_workspace_names and dep != name]

    source_dirs = []
    for d in ["src", "lib", "app"]:
        if os.path.isdir(os.path.join(root_dir, ws_dir, d)):
            source_dirs.append(os.path.join(ws_dir, d))
    test_dirs = []
    for d in ["test", "tests", "__tests__", "spec"]:
        if os.path.isdir(os.path.join(root_dir, ws_dir, d)):
            test_dirs.append(os.path.join(ws_dir, d))

    result["modules"].append({
        "name": name, "artifact_id": name, "directory": ws_dir,
        "source_dirs": source_dirs or [ws_dir],
        "test_dirs": test_dirs,
        "depends_on": cross_deps
    })

for mod in result["modules"]:
    mod["depended_by"] = [m["name"] for m in result["modules"] if mod["name"] in m.get("depends_on", [])]

json.dump(result, sys.stdout, indent=2)
PYEOF
}

# -- .NET solution discovery -------------------------------------------------

discover_dotnet_modules() {
  local root="$1"

  "${FORGE_PYTHON:-python3}" << 'PYEOF' - "$root"
import os, sys, json, re
import xml.etree.ElementTree as ET

root_dir = sys.argv[1]
result = {"build_system": "dotnet", "root": root_dir, "modules": []}

sln_files = [f for f in os.listdir(root_dir) if f.endswith('.sln')]

projects = []

if sln_files:
    sln_path = os.path.join(root_dir, sln_files[0])
    with open(sln_path, 'r') as f:
        for line in f:
            m = re.match(r'^Project\("[^"]*"\)\s*=\s*"([^"]+)",\s*"([^"]+)"', line)
            if m:
                name = m.group(1)
                proj_path = m.group(2).replace('\\', '/')
                if proj_path.endswith('.csproj'):
                    projects.append((name, proj_path))
else:
    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in ('bin', 'obj', '.git', 'node_modules')]
        for fn in filenames:
            if fn.endswith('.csproj'):
                rel = os.path.relpath(os.path.join(dirpath, fn), root_dir)
                name = fn.replace('.csproj', '')
                projects.append((name, rel))

for proj_name, csproj_rel in projects:
    csproj_path = os.path.join(root_dir, csproj_rel)
    proj_dir = os.path.dirname(csproj_rel)

    depends_on = []
    try:
        tree = ET.parse(csproj_path)
        for ref in tree.findall('.//ProjectReference'):
            include = ref.get('Include', '').replace('\\', '/')
            ref_name = os.path.splitext(os.path.basename(include))[0]
            depends_on.append(ref_name)
    except ET.ParseError:
        pass

    source_dirs = [proj_dir] if proj_dir else ["."]
    test_dirs = []
    if any(proj_name.endswith(suffix) for suffix in ['.Tests', '.Test', 'Tests', 'Test']):
        test_dirs = source_dirs
        source_dirs = []

    result["modules"].append({
        "name": proj_name, "artifact_id": proj_name, "directory": proj_dir or ".",
        "source_dirs": source_dirs, "test_dirs": test_dirs,
        "depends_on": depends_on
    })

for mod in result["modules"]:
    mod["depended_by"] = [m["name"] for m in result["modules"] if mod["name"] in m.get("depends_on", [])]

json.dump(result, sys.stdout, indent=2)
PYEOF
}

# -- Auto-detect build system ------------------------------------------------

auto_detect_build_system() {
  local root="$1"

  [[ -f "$root/pom.xml" ]] && { echo "maven"; return; }
  [[ -f "$root/build.gradle" || -f "$root/build.gradle.kts" ]] && { echo "gradle"; return; }
  [[ -f "$root/Cargo.toml" ]] && { echo "cargo"; return; }
  [[ -f "$root/go.mod" || -f "$root/go.work" ]] && { echo "go"; return; }
  [[ -f "$root/package.json" ]] && { echo "npm"; return; }
  _glob_exists "$root"/*.sln && { echo "dotnet"; return; }
  _glob_exists "$root"/*.csproj && { echo "dotnet"; return; }

  echo "none"
}

# -- Main --------------------------------------------------------------------

main() {
  parse_args "$@"

  local detected_system="$BUILD_SYSTEM"
  if [[ "$detected_system" == "auto" ]]; then
    detected_system="$(auto_detect_build_system "$PROJECT_ROOT")"
  fi

  local result=""
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"

  case "$detected_system" in
    maven)  result="$(discover_maven_modules "$PROJECT_ROOT")" ;;
    gradle) result="$(discover_gradle_modules "$PROJECT_ROOT")" ;;
    cargo)  result="$(discover_cargo_modules "$PROJECT_ROOT")" ;;
    go)     result="$(discover_go_modules "$PROJECT_ROOT")" ;;
    npm|pnpm|yarn) result="$(discover_js_modules "$PROJECT_ROOT")" ;;
    dotnet) result="$(discover_dotnet_modules "$PROJECT_ROOT")" ;;
    *)
      result='{"version":"1.0.0","build_system":"none","root":"'"$PROJECT_ROOT"'","generated_at":"'"$now"'","resolution_mode":"heuristic","modules":[]}'
      ;;
  esac

  # Ensure version and generated_at are present
  result="$(echo "$result" | "${FORGE_PYTHON:-python3}" -c "
import json, sys
data = json.load(sys.stdin)
data.setdefault('version', '1.0.0')
data.setdefault('generated_at', sys.argv[1])
data.setdefault('resolution_mode', 'parsed')
json.dump(data, sys.stdout, indent=2)
" "$now")"

  if [[ -n "$OUTPUT_FILE" ]]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    echo "$result" > "$OUTPUT_FILE"
    echo "[boundary-map] Wrote module boundary map to $OUTPUT_FILE" >&2
  else
    echo "$result"
  fi
}

if [[ "$_SOURCE_ONLY" != "true" ]]; then
  main "$@"
fi
