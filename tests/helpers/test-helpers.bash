#!/usr/bin/env bash
# Shared test helpers for forge bats test suite.
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
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"

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
# get_frontmatter <file>
# Extracts YAML frontmatter between the first two --- delimiters.
# ---------------------------------------------------------------------------
get_frontmatter() {
  awk '/^---$/{n++; if(n==2) exit; next} n==1{print}' "$1"
}

# ---------------------------------------------------------------------------
# extract_mcp_list
# Parses MCP names from CLAUDE.md "Detects" line.
# Returns one MCP name per line.
# ---------------------------------------------------------------------------
extract_mcp_list() {
  local line
  line="$(grep -i "Detects.*Linear" "$PLUGIN_ROOT/CLAUDE.md" | head -1)"
  echo "$line" | sed 's/.*Detects //' | sed 's/\..*//' | tr ',' '\n' | sed 's/^ *//' | sed 's/ *$//'
}

# ---------------------------------------------------------------------------
# create_temp_project <module>
# Creates a minimal fake project directory whose layout triggers module
# detection in engine.sh.  Runs git init and creates .forge/.
# Prints the absolute project path to stdout.
# ---------------------------------------------------------------------------
create_temp_project() {
  local module="${1:?create_temp_project requires a module name}"
  local project_dir="${TEST_TEMP}/projects/${module}"
  mkdir -p "${project_dir}"

  case "${module}" in
    spring)
      printf 'plugins { id("org.springframework.boot") }\n' > "${project_dir}/build.gradle.kts"
      mkdir -p "${project_dir}/src/main/kotlin"
      ;;
    spring-java)
      printf 'plugins { id("org.springframework.boot") }\n' > "${project_dir}/build.gradle.kts"
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
      printf '[package]\nname = "test-app"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\naxum = "0.7"\n' \
        > "${project_dir}/Cargo.toml"
      ;;
    go-stdlib)
      printf 'module example.com/test-app\n\ngo 1.21\n' > "${project_dir}/go.mod"
      ;;
    fastapi)
      printf '[project]\nname = "test-app"\nversion = "0.1.0"\ndependencies = ["fastapi>=0.100"]\n' \
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
    angular)
      echo '{"name":"test-app","version":"0.0.1"}' > "${project_dir}/package.json"
      printf '{\n  "$schema": "./node_modules/@angular/cli/lib/config/schema.json"\n}\n' \
        > "${project_dir}/angular.json"
      ;;
    nestjs)
      echo '{"name":"test-app","version":"0.0.1","dependencies":{"@nestjs/core":"10.0.0"}}' \
        > "${project_dir}/package.json"
      printf '{\n  "compilerOptions": { "module": "commonjs" }\n}\n' \
        > "${project_dir}/nest-cli.json"
      ;;
    svelte)
      echo '{"name":"test-app","version":"0.0.1","devDependencies":{"svelte":"5.0.0"}}' \
        > "${project_dir}/package.json"
      ;;
    vue)
      echo '{"name":"test-app","version":"0.0.1","dependencies":{"vue":"3.4.0"}}' \
        > "${project_dir}/package.json"
      printf 'import { fileURLToPath } from "node:url";\nimport vue from "@vitejs/plugin-vue";\n' \
        > "${project_dir}/vite.config.ts"
      ;;
    aspnet)
      cat > "${project_dir}/TestApp.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
CSPROJ
      ;;
    django)
      printf '#!/usr/bin/env python\nimport os, sys\nif __name__ == "__main__":\n    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "app.settings")\n' \
        > "${project_dir}/manage.py"
      printf 'django>=5.0\n' > "${project_dir}/requirements.txt"
      ;;
    nextjs)
      echo '{"name":"test-app","version":"0.0.1","dependencies":{"next":"14.0.0","react":"18.2.0"}}' \
        > "${project_dir}/package.json"
      printf '/** @type {import("next").NextConfig} */\nconst nextConfig = {};\nmodule.exports = nextConfig;\n' \
        > "${project_dir}/next.config.js"
      ;;
    gin)
      printf 'module example.com/test-app\n\ngo 1.21\n\nrequire github.com/gin-gonic/gin v1.9.1\n' \
        > "${project_dir}/go.mod"
      ;;
    jetpack-compose)
      cat > "${project_dir}/build.gradle.kts" <<'GRADLE'
plugins {
    id("com.android.application")
    kotlin("android")
}
android {
    compileSdk = 34
    buildFeatures { compose = true }
}
dependencies {
    implementation("androidx.compose.ui:ui:1.5.0")
    implementation("androidx.compose.material3:material3:1.1.0")
}
GRADLE
      ;;
    kotlin-multiplatform)
      mkdir -p "${project_dir}/src/commonMain"
      cat > "${project_dir}/build.gradle.kts" <<'GRADLE'
plugins {
    kotlin("multiplatform") version "2.0.0"
}
kotlin {
    jvm()
    js(IR) { browser() }
}
GRADLE
      ;;
    *)
      echo "create_temp_project: unknown module '${module}'" >&2
      return 1
      ;;
  esac

  # Every project gets a git repo and a .forge dir
  mkdir -p "${project_dir}/.forge"
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
# Creates .forge/state.json inside TEST_TEMP/project with base v1.0.0 fields.
# Optionally merges extra_json (a JSON object string) on top via python/jq.
# Prints the absolute path to the created file.
# ---------------------------------------------------------------------------
create_state_json() {
  local extra_json="${1:-{\}}"
  local state_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "${state_dir}"
  local state_file="${state_dir}/state.json"

  # Base v1.5.0 state object (matches state-schema.md v1.5.0)
  local base_json
  base_json=$(cat <<'EOF'
{
  "version": "1.5.0",
  "_seq": 0,
  "complete": false,
  "story_id": "TEST-001",
  "requirement": "Test requirement",
  "domain_area": "test",
  "risk_level": "LOW",
  "previous_state": "",
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
  "run_id": "test-run-001",
  "quality_cycles": 0,
  "test_cycles": 0,
  "verify_fix_count": 0,
  "validation_retries": 0,
  "total_retries": 0,
  "total_retries_max": 10,
  "stage_timestamps": {},
  "last_commit_sha": "",
  "preempt_items_applied": [],
  "preempt_items_status": {},
  "feedback_classification": "",
  "previous_feedback_classification": "",
  "feedback_loop_count": 0,
  "score_history": [],
  "convergence": {
    "phase": "correctness",
    "phase_iterations": 0,
    "total_iterations": 0,
    "plateau_count": 0,
    "last_score_delta": 0,
    "convergence_state": "IMPROVING",
    "phase_history": [],
    "safety_gate_passed": false,
    "safety_gate_failures": 0,
    "unfixable_findings": [],
    "diminishing_count": 0
  },
  "integrations": {
    "linear": { "available": false, "team": "" },
    "playwright": { "available": false },
    "slack": { "available": false },
    "figma": { "available": false },
    "context7": { "available": false },
    "neo4j": { "available": false, "last_build_sha": "", "node_count": 0 }
  },
  "linear": {
    "epic_id": "",
    "story_ids": [],
    "task_ids": {}
  },
  "linear_sync": {
    "in_sync": true,
    "failed_operations": []
  },
  "modules": [],
  "cost": {
    "wall_time_seconds": 0,
    "stages_completed": 0
  },
  "recovery_budget": {
    "total_weight": 0.0,
    "max_weight": 5.5,
    "applications": []
  },
  "recovery": {
    "total_failures": 0,
    "total_recoveries": 0,
    "degraded_capabilities": [],
    "failures": [],
    "budget_warning_issued": false
  },
  "scout_improvements": 0,
  "conventions_hash": "",
  "conventions_section_hashes": {},
  "detected_versions": {},
  "check_engine_skipped": 0,
  "mode": "standard",
  "dry_run": false,
  "cross_repo": {},
  "spec": null,
  "documentation": {
    "discovery_error": false,
    "last_discovery_timestamp": "",
    "files_discovered": 0,
    "sections_parsed": 0,
    "decisions_extracted": 0,
    "constraints_extracted": 0,
    "code_linkages": 0,
    "coverage_gaps": [],
    "stale_sections": 0,
    "external_refs": [],
    "generation_history": [],
    "generation_error": false
  },
  "exploration_degraded": false,
  "oscillation_tolerance": 5,
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

# --- Tracking helpers ---

setup_tracking() {
  local forge_dir="$1"
  mkdir -p "$forge_dir/tracking/backlog" "$forge_dir/tracking/in-progress" "$forge_dir/tracking/review" "$forge_dir/tracking/done"
  echo '{"next": 1, "prefix": "FG"}' > "$forge_dir/tracking/counter.json"
}

# ---------------------------------------------------------------------------
# create_score_sequence_state <scores_string> [extra_json]
# Creates a state.json with score_history set from a space-separated score
# array. Computes convergence fields automatically:
#   - convergence.total_iterations = length of score array
#   - convergence.phase_iterations = length of score array (single phase)
#   - convergence.last_score_delta = last - second-to-last (or 0 if only 1)
#   - convergence.convergence_state = "IMPROVING" (caller overrides if needed)
#   - convergence.plateau_count = 0 (caller overrides if needed)
#   - convergence.phase = "correctness"
#   - story_state defaults to "REVIEWING" (caller overrides via extra_json)
#
# Usage: create_score_sequence_state "78 82 77 83" '{"oscillation_tolerance": 5}'
# ---------------------------------------------------------------------------
create_score_sequence_state() {
  local scores_str="${1:?scores required}"
  local extra="${2:-\{\}}"
  local -a scores=($scores_str)
  local len=${#scores[@]}
  local last_delta=0
  if (( len >= 2 )); then
    last_delta=$(( scores[len-1] - scores[len-2] ))
  fi
  local score_json
  score_json=$(printf '%s\n' "${scores[@]}" | jq -s '.')
  local conv_extra
  conv_extra=$(jq -n \
    --argjson sh "$score_json" \
    --argjson ti "$len" \
    --argjson pi "$len" \
    --argjson ld "$last_delta" \
    '{
      story_state: "REVIEWING",
      score_history: $sh,
      convergence: {
        total_iterations: $ti,
        phase_iterations: $pi,
        last_score_delta: $ld
      }
    }')
  # Merge conv_extra with caller extra
  local merged
  merged=$(printf '%s\n%s\n' "$conv_extra" "$extra" | jq -s '.[0] * .[1]')
  create_state_json "$merged"
}

# ---------------------------------------------------------------------------
# assert_convergence_state <expected> [forge_dir]
# Reads convergence.convergence_state from state.json and asserts equality.
# ---------------------------------------------------------------------------
assert_convergence_state() {
  local expected="${1:?expected state required}"
  local forge_dir="${2:-${TEST_TEMP}/project/.forge}"
  local actual
  actual="$(jq -r '.convergence.convergence_state' "$forge_dir/state.json")"
  [[ "$actual" == "$expected" ]] || fail "Expected convergence_state=$expected, got $actual"
}

# ---------------------------------------------------------------------------
# assert_story_state <expected> [forge_dir]
# Reads story_state from state.json and asserts equality.
# ---------------------------------------------------------------------------
assert_story_state() {
  local expected="${1:?expected state required}"
  local forge_dir="${2:-${TEST_TEMP}/project/.forge}"
  local actual
  actual="$(jq -r '.story_state' "$forge_dir/state.json")"
  [[ "$actual" == "$expected" ]] || fail "Expected story_state=$expected, got $actual"
}
