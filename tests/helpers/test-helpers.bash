#!/usr/bin/env bash
# Shared test helpers for dev-pipeline bats test suite.
# Load with: load '../helpers/test-helpers'  (from unit/, contract/, or scenario/)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# PLUGIN_ROOT: two levels up from tests/helpers/ → plugin root
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Load bats-support and bats-assert for rich assertions
load "${PLUGIN_ROOT}/tests/lib/bats-support/load"
load "${PLUGIN_ROOT}/tests/lib/bats-assert/load"

# ---------------------------------------------------------------------------
# setup / teardown — called automatically by bats for every test
# ---------------------------------------------------------------------------

setup() {
  # Unique temp dir per test to avoid cross-test pollution
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-dev-pipeline.XXXXXX")"

  # Dedicated bin dir for mock executables; prepended to PATH
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"

  # Project dir used by create_temp_file and create_state_json
  mkdir -p "${TEST_TEMP}/project"
}

teardown() {
  if [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]]; then
    rm -rf "${TEST_TEMP}"
  fi
}

# ---------------------------------------------------------------------------
# create_temp_project <module>
# Creates a minimal fake project directory whose layout triggers module
# detection in engine.sh.  Runs git init and creates .pipeline/.
# Prints the absolute project path to stdout.
# ---------------------------------------------------------------------------
create_temp_project() {
  local module="${1:?create_temp_project requires a module name}"
  local project_dir="${TEST_TEMP}/projects/${module}"
  mkdir -p "${project_dir}"

  case "${module}" in
    spring)
      touch "${project_dir}/build.gradle.kts"
      mkdir -p "${project_dir}/src/main/kotlin"
      ;;
    spring-java)
      touch "${project_dir}/build.gradle.kts"
      mkdir -p "${project_dir}/src/main/java"
      ;;
    react)
      echo '{"name":"test-app","version":"0.0.1"}' > "${project_dir}/package.json"
      touch "${project_dir}/vite.config.ts"
      ;;
    sveltekit)
      echo '{"name":"test-app","version":"0.0.1"}' > "${project_dir}/package.json"
      touch "${project_dir}/svelte.config.js"
      ;;
    express)
      echo '{"name":"test-app","version":"0.0.1"}' > "${project_dir}/package.json"
      ;;
    axum)
      printf '[package]\nname = "test-app"\nversion = "0.1.0"\nedition = "2021"\n' \
        > "${project_dir}/Cargo.toml"
      ;;
    go-stdlib)
      printf 'module example.com/test-app\n\ngo 1.21\n' > "${project_dir}/go.mod"
      ;;
    fastapi)
      printf '[project]\nname = "test-app"\nversion = "0.1.0"\n' \
        > "${project_dir}/pyproject.toml"
      ;;
    vapor)
      printf '// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "test-app")\n' \
        > "${project_dir}/Package.swift"
      ;;
    swiftui)
      mkdir -p "${project_dir}/test-app.xcodeproj"
      touch "${project_dir}/test-app.xcodeproj/project.pbxproj"
      ;;
    embedded)
      touch "${project_dir}/Makefile"
      touch "${project_dir}/main.c"
      ;;
    k8s)
      mkdir -p "${project_dir}/k8s"
      touch "${project_dir}/k8s/deployment.yaml"
      ;;
    *)
      echo "create_temp_project: unknown module '${module}'" >&2
      return 1
      ;;
  esac

  # Every project gets a git repo and a .pipeline dir
  mkdir -p "${project_dir}/.pipeline"
  git -C "${project_dir}" init -q
  git -C "${project_dir}" config user.email "test@example.com"
  git -C "${project_dir}" config user.name "Test"

  printf '%s' "${project_dir}"
}

# ---------------------------------------------------------------------------
# create_temp_file <subpath> <content>
# Creates TEST_TEMP/project/<subpath> with the given content.
# Prints the absolute file path to stdout.
# ---------------------------------------------------------------------------
create_temp_file() {
  local subpath="${1:?create_temp_file requires a subpath}"
  local content="${2:-}"
  local abs_path="${TEST_TEMP}/project/${subpath}"
  mkdir -p "$(dirname "${abs_path}")"
  printf '%s' "${content}" > "${abs_path}"
  printf '%s' "${abs_path}"
}

# ---------------------------------------------------------------------------
# create_state_json [extra_json]
# Creates .pipeline/state.json inside TEST_TEMP/project with base v1.0.0 fields.
# Optionally merges extra_json (a JSON object string) on top via python/jq.
# Prints the absolute path to the created file.
# ---------------------------------------------------------------------------
create_state_json() {
  local extra_json="${1:-{\}}"
  local state_dir="${TEST_TEMP}/project/.pipeline"
  mkdir -p "${state_dir}"
  local state_file="${state_dir}/state.json"

  # Base v1.0.0 state object
  local base_json
  base_json=$(cat <<'EOF'
{
  "version": "1.0.0",
  "story_state": "PREFLIGHT",
  "active_component": "default",
  "components": {
    "default": {
      "story_state": "PREFLIGHT",
      "conventions_hash": "",
      "conventions_section_hashes": {},
      "detected_versions": {}
    }
  },
  "story_id": "TEST-001",
  "run_id": "test-run-001",
  "total_retries": 0,
  "total_retries_max": 10,
  "oscillation_tolerance": 5,
  "detected_versions": {},
  "linear_sync": {},
  "preempt_items_status": {},
  "stage_notes": {},
  "quality_score": null,
  "worktree_branch": null,
  "lock_pid": null
}
EOF
)

  # Merge extra_json into base if python3 is available, else just write base
  if command -v python3 &>/dev/null; then
    python3 - "${base_json}" "${extra_json}" <<'PYEOF' > "${state_file}"
import json, sys
base = json.loads(sys.argv[1])
extra = json.loads(sys.argv[2])
base.update(extra)
print(json.dumps(base, indent=2))
PYEOF
  elif command -v jq &>/dev/null; then
    printf '%s\n%s\n' "${base_json}" "${extra_json}" \
      | jq -s '.[0] * .[1]' > "${state_file}"
  else
    printf '%s\n' "${base_json}" > "${state_file}"
  fi

  printf '%s' "${state_file}"
}

# ---------------------------------------------------------------------------
# mock_command <name> <body>
# Creates an executable script in MOCK_BIN named <name>.
# <body> is the script body (without shebang).
# ---------------------------------------------------------------------------
mock_command() {
  local name="${1:?mock_command requires a name}"
  local body="${2:?mock_command requires a body}"
  local mock_path="${MOCK_BIN}/${name}"
  printf '#!/usr/bin/env bash\n%s\n' "${body}" > "${mock_path}"
  chmod +x "${mock_path}"
}

# ---------------------------------------------------------------------------
# assert_finding_format <output>
# Validates that each non-empty line of <output> matches the check-engine
# output format:   file:line | CATEGORY-CODE | SEVERITY | message | fix_hint
# Fails the test if any line does not conform.
# ---------------------------------------------------------------------------
assert_finding_format() {
  local output="${1}"
  local line_num=0
  while IFS= read -r line; do
    line_num=$(( line_num + 1 ))
    # Skip empty lines
    [[ -z "${line}" ]] && continue
    # Pattern: <file>:<line_no> | <CATEGORY-CODE> | <SEVERITY> | <message> | <fix_hint>
    # SEVERITY must be CRITICAL, WARNING, or INFO
    if ! printf '%s' "${line}" | grep -qE \
      '^[^|]+:[0-9]+ \| [A-Z]+-[A-Z0-9_-]+ \| (CRITICAL|WARNING|INFO) \| .* \| .*$'; then
      fail "Line ${line_num} does not match finding format: ${line}"
    fi
  done <<< "${output}"
}

# ---------------------------------------------------------------------------
# assert_no_findings <output>
# Fails the test if output contains any non-empty lines.
# ---------------------------------------------------------------------------
assert_no_findings() {
  local output="${1}"
  local trimmed
  trimmed="$(printf '%s' "${output}" | tr -d '[:space:]')"
  if [[ -n "${trimmed}" ]]; then
    fail "Expected no findings but got output: ${output}"
  fi
}
