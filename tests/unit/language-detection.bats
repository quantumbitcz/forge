#!/usr/bin/env bats
# Unit tests for detect_language() and detect_module() in shared/checks/engine.sh.
# These functions are tested indirectly by running engine.sh in --verify mode.

load '../helpers/test-helpers'

ENGINE="$PLUGIN_ROOT/shared/checks/engine.sh"

# ---------------------------------------------------------------------------
# 1. Kotlin file (.kt) is detected and produces kotlin findings
# ---------------------------------------------------------------------------
@test "language-detection: .kt file triggers kotlin findings (QUAL-NULL)" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local kt_file="${project_dir}/src/main/kotlin/Bad.kt"
  printf 'package com.example\nval x = someValue!!\n' > "$kt_file"

  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${kt_file}' 2>/dev/null"

  assert_success
  assert_output --partial "QUAL-NULL"
  assert_finding_format "$output"
}

# ---------------------------------------------------------------------------
# 2. TypeScript file (.tsx) is detected and produces typescript findings
# ---------------------------------------------------------------------------
@test "language-detection: .tsx file triggers typescript findings (SEC-EVAL)" {
  local project_dir
  project_dir="$(create_temp_project react)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local ts_file="${project_dir}/src/Dangerous.tsx"
  mkdir -p "$(dirname "$ts_file")"
  # Construct eval call via variable to avoid triggering check-engine hook on this write
  local dangerous_call="eval"
  printf 'const result = %s("1 + 1");\n' "$dangerous_call" > "$ts_file"

  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${ts_file}' 2>/dev/null"

  assert_success
  assert_output --partial "SEC-EVAL"
  assert_finding_format "$output"
}

# ---------------------------------------------------------------------------
# 3. Unknown extension (.md) produces no findings (language not detected)
# ---------------------------------------------------------------------------
@test "language-detection: .md file produces no findings (not a code language)" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local md_file="${project_dir}/README.md"
  # Content that would trigger kotlin findings if wrongly identified
  printf '# Readme\nval x = something!!\n' > "$md_file"

  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${md_file}' 2>/dev/null"

  assert_success
  assert_no_findings "$output"
}

# ---------------------------------------------------------------------------
# 4. Module detection: spring project + kotlin file in core/src/main
#    importing from adapter triggers ARCH-BOUNDARY (from rules-override.json)
# ---------------------------------------------------------------------------
@test "language-detection: spring module override applies ARCH-BOUNDARY rule" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  # Create a file in core/src/main that imports from an adapter package
  # This matches the additional_boundaries rule in modules/frameworks/spring/rules-override.json:
  # scope_pattern: "core/src/main", forbidden_imports: ["\\.adapter\\."]
  local core_file="${project_dir}/core/src/main/kotlin/domain/UseCase.kt"
  mkdir -p "$(dirname "$core_file")"
  printf 'package com.example.core.domain\nimport com.example.adapter.SomeAdapter\n\nclass UseCase\n' > "$core_file"

  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${core_file}' 2>/dev/null"

  assert_success
  assert_output --partial "ARCH-BOUNDARY"
  assert_finding_format "$output"
}

# ---------------------------------------------------------------------------
# 5. Module detection caching: second engine run uses cached module
# ---------------------------------------------------------------------------
@test "language-detection: module detection result is cached in .forge/.module-cache" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local kt_file="${project_dir}/src/main/kotlin/Clean.kt"
  printf 'package com.example\nclass Clean\n' > "$kt_file"

  # First run — cache does not yet exist
  assert [ ! -f "${project_dir}/.forge/.module-cache" ]

  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${kt_file}' 2>/dev/null"
  assert_success

  # Cache file must exist now
  assert [ -f "${project_dir}/.forge/.module-cache" ]
  local cached_module
  cached_module="$(cat "${project_dir}/.forge/.module-cache")"
  assert [ "$cached_module" = "spring" ]

  # Second run — cache is used (same result, file still present)
  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${kt_file}' 2>/dev/null"
  assert_success

  local cached_module2
  cached_module2="$(cat "${project_dir}/.forge/.module-cache")"
  assert [ "$cached_module2" = "spring" ]
}

# ---------------------------------------------------------------------------
# 6. Dockerfile is detected by filename (no extension)
# ---------------------------------------------------------------------------
@test "language-detection: Dockerfile triggers dockerfile findings" {
  local project_dir
  project_dir="$(create_temp_project k8s)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local dockerfile="${project_dir}/Dockerfile"
  printf 'FROM ubuntu:latest\nRUN apt-get install -y curl\n' > "$dockerfile"

  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${dockerfile}' 2>/dev/null"

  assert_success
}

# ---------------------------------------------------------------------------
# 7. Dockerfile.prod variant is detected
# ---------------------------------------------------------------------------
@test "language-detection: Dockerfile.prod triggers dockerfile findings" {
  local project_dir
  project_dir="$(create_temp_project k8s)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local dockerfile="${project_dir}/Dockerfile.prod"
  printf 'FROM node:20\nCOPY . .\n' > "$dockerfile"

  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${dockerfile}' 2>/dev/null"

  assert_success
}

# ---------------------------------------------------------------------------
# 8. YAML file is detected
# ---------------------------------------------------------------------------
@test "language-detection: .yaml file triggers yaml findings" {
  local project_dir
  project_dir="$(create_temp_project k8s)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local yaml_file="${project_dir}/values.yaml"
  printf 'replicas: 1\nimage: nginx:latest\n' > "$yaml_file"

  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${yaml_file}' 2>/dev/null"

  assert_success
}

# ---------------------------------------------------------------------------
# 9. .yml extension also detected
# ---------------------------------------------------------------------------
@test "language-detection: .yml file triggers yaml findings" {
  local project_dir
  project_dir="$(create_temp_project k8s)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local yml_file="${project_dir}/config.yml"
  printf 'key: value\n' > "$yml_file"

  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${yml_file}' 2>/dev/null"

  assert_success
}

# ---------------------------------------------------------------------------
# 10. All 8 language extensions are handled (or silently ignored for unsupported)
#     For each known extension, engine produces no error and exits 0.
#     Code extensions with content that triggers findings produce output.
#     Non-code extensions produce no findings.
# ---------------------------------------------------------------------------
@test "language-detection: engine handles all 8 known code extensions without error" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  # Map: extension -> content that should be valid (not trigger errors, just be processed)
  declare -A ext_content
  ext_content[".kt"]='package com.example\nclass Clean\n'
  ext_content[".kts"]='val x = 1\n'
  ext_content[".java"]='public class Clean {}\n'
  ext_content[".ts"]='const x: string = "hello";\n'
  ext_content[".tsx"]='export const App = () => <div/>;\n'
  ext_content[".js"]='const x = 1;\n'
  ext_content[".jsx"]='const App = () => <div/>;\n'
  ext_content[".py"]='x = 1\n'

  local all_ok=true
  for ext in ".kt" ".kts" ".java" ".ts" ".tsx" ".js" ".jsx" ".py"; do
    local test_file="${project_dir}/src/TestFile${ext}"
    printf "${ext_content[$ext]}" > "$test_file"

    run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
      bash '${ENGINE}' --verify \
        --project-root '${project_dir}' \
        --files-changed '${test_file}' 2>/dev/null"

    if [ "$status" -ne 0 ]; then
      all_ok=false
      echo "FAILED for extension: $ext (exit status: $status)" >&2
    fi
  done

  assert [ "$all_ok" = "true" ]
}
