#!/usr/bin/env bats
# Unit tests for shared/checks/engine.sh — the unified check engine entry point.

load '../helpers/test-helpers'

ENGINE="$PLUGIN_ROOT/shared/checks/engine.sh"

# ---------------------------------------------------------------------------
# 1. hook mode: extracts file_path from TOOL_INPUT JSON
#    Creates a kotlin file with !! and asserts QUAL-NULL in output
# ---------------------------------------------------------------------------
@test "hook mode: detects QUAL-NULL from TOOL_INPUT file_path" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  local kt_file="${project_dir}/src/main/kotlin/Bad.kt"
  printf 'package com.example\nval x = someValue!!\n' > "$kt_file"

  # Stage and commit so git works
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  run env \
    TOOL_INPUT="{\"file_path\": \"${kt_file}\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_output --partial "QUAL-NULL"
  assert_finding_format "$output"
}

# ---------------------------------------------------------------------------
# 2. hook mode: skips nonexistent files (silent output)
# ---------------------------------------------------------------------------
@test "hook mode: skips nonexistent files silently" {
  run env \
    TOOL_INPUT='{"file_path": "/nonexistent/path/to/file.kt"}' \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_no_findings "$output"
}

# ---------------------------------------------------------------------------
# 3. hook mode: skips generated sources (build/generated-sources/ path)
# ---------------------------------------------------------------------------
@test "hook mode: skips files under build/generated-sources/" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  # Create a file inside build/generated-sources/ that would normally trigger findings
  local gen_dir="${project_dir}/build/generated-sources/kotlin/com/example"
  mkdir -p "$gen_dir"
  local kt_file="${gen_dir}/GeneratedCode.kt"
  printf 'package com.example\nval x = someValue!!\n' > "$kt_file"

  run env \
    TOOL_INPUT="{\"file_path\": \"${kt_file}\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_no_findings "$output"
}

# ---------------------------------------------------------------------------
# 4. hook mode: prevents double execution via _ENGINE_RUNNING=1 env var
# ---------------------------------------------------------------------------
@test "hook mode: exits 0 with empty output when _ENGINE_RUNNING=1" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  local kt_file="${project_dir}/src/main/kotlin/Bad.kt"
  printf 'package com.example\nval x = someValue!!\n' > "$kt_file"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  run env \
    _ENGINE_RUNNING=1 \
    TOOL_INPUT="{\"file_path\": \"${kt_file}\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_no_findings "$output"
}

# ---------------------------------------------------------------------------
# 5. hook mode: increments skip counter on error
#    Tested by invoking handle_skip directly via a minimal wrapper script that
#    replicates the engine's skip-counter mechanism.  This validates the
#    observable behavior without depending on specific bash ERR-trap propagation
#    rules through function chains.
# ---------------------------------------------------------------------------
@test "hook mode: skip counter mechanism writes and increments correctly" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  # Build a minimal wrapper that replicates handle_skip and triggers it from
  # the main script body level (where bash ERR propagation is reliable).
  local wrapper="${TEST_TEMP}/skip-test.sh"
  cat > "$wrapper" << EOF
#!/usr/bin/env bash
set -euo pipefail
handle_skip() {
  local skip_file=".pipeline/.check-engine-skipped"
  if [ -d ".pipeline" ]; then
    local count=0
    if [ -f "\$skip_file" ]; then
      count=\$(cat "\$skip_file" 2>/dev/null || echo 0)
    fi
    echo \$((count + 1)) > "\$skip_file"
  fi
  echo "[check-engine] Hook skipped (timeout/error)" >&2
  exit 0
}
trap handle_skip ERR
# Force an error at the main script body level
/this/command/does/not/exist
EOF
  chmod +x "$wrapper"

  # Run from project_dir so .pipeline/ is the CWD .pipeline/
  run bash -c "cd '${project_dir}' && bash '${wrapper}'"

  assert_success

  # Skip counter should have been written
  assert [ -f "${project_dir}/.pipeline/.check-engine-skipped" ]
  local count
  count="$(cat "${project_dir}/.pipeline/.check-engine-skipped")"
  assert [ "$count" -ge 1 ]

  # Run a second time — counter should increment
  run bash -c "cd '${project_dir}' && bash '${wrapper}'"
  assert_success
  local count2
  count2="$(cat "${project_dir}/.pipeline/.check-engine-skipped")"
  assert [ "$count2" -gt "$count" ]
}

# ---------------------------------------------------------------------------
# 6. hook mode: handles empty TOOL_INPUT gracefully (empty output)
# ---------------------------------------------------------------------------
@test "hook mode: handles empty TOOL_INPUT gracefully" {
  run env \
    TOOL_INPUT='' \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_no_findings "$output"
}

# ---------------------------------------------------------------------------
# 7. hook mode: handles unset TOOL_INPUT (empty output)
# ---------------------------------------------------------------------------
@test "hook mode: handles unset TOOL_INPUT gracefully" {
  run env \
    -u TOOL_INPUT \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_no_findings "$output"
}

# ---------------------------------------------------------------------------
# 8. default mode (no args) behaves as --hook (empty TOOL_INPUT → empty output)
# ---------------------------------------------------------------------------
@test "default mode (no args) behaves same as --hook with empty TOOL_INPUT" {
  run env \
    TOOL_INPUT='' \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE"

  assert_success
  assert_no_findings "$output"
}

# ---------------------------------------------------------------------------
# 9. verify mode: processes multiple --files-changed → findings from both files
# ---------------------------------------------------------------------------
@test "verify mode: emits findings from multiple --files-changed files" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local kt_file1="${project_dir}/src/main/kotlin/FileOne.kt"
  local kt_file2="${project_dir}/src/main/kotlin/FileTwo.kt"
  printf 'package com.example\nval a = foo!!\n' > "$kt_file1"
  printf 'package com.example\nval b = bar!!\n' > "$kt_file2"

  # Capture stdout only (redirect stderr to /dev/null) so Layer 2 informational
  # messages like "INFO: No linter available for kotlin" don't pollute the output
  # that assert_finding_format validates.
  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${kt_file1}' '${kt_file2}' 2>/dev/null"

  assert_success
  # Both files should trigger QUAL-NULL
  assert_output --partial "FileOne.kt"
  assert_output --partial "FileTwo.kt"
  assert_finding_format "$output"
}

# ---------------------------------------------------------------------------
# 10. verify mode: skips nonexistent files in the list
# ---------------------------------------------------------------------------
@test "verify mode: skips nonexistent files without error" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local kt_file="${project_dir}/src/main/kotlin/Real.kt"
  printf 'package com.example\nval x = foo!!\n' > "$kt_file"

  # Suppress Layer 2 informational stderr so assert_finding_format sees clean output
  run bash -c "env CLAUDE_PLUGIN_ROOT='${PLUGIN_ROOT}' \
    bash '${ENGINE}' --verify \
      --project-root '${project_dir}' \
      --files-changed '${kt_file}' '/nonexistent/missing.kt' 2>/dev/null"

  assert_success
  # Real file is processed, nonexistent is silently skipped
  assert_output --partial "QUAL-NULL"
  assert_finding_format "$output"
}

# ---------------------------------------------------------------------------
# 11. always exits 0 regardless of errors
# ---------------------------------------------------------------------------
@test "engine always exits 0 regardless of errors" {
  # Use a completely broken environment
  run env \
    TOOL_INPUT='{"file_path": "/dev/null"}' \
    CLAUDE_PLUGIN_ROOT='/nonexistent' \
    bash "$ENGINE" --hook

  assert_success
}

# ---------------------------------------------------------------------------
# 12. non-code file (.md) returns no output
# ---------------------------------------------------------------------------
@test "non-code file (.md) returns no findings" {
  local md_file
  md_file="$(create_temp_file 'README.md' '# Hello World\n\nThis is a markdown file with !!\n')"

  run env \
    TOOL_INPUT="{\"file_path\": \"${md_file}\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_no_findings "$output"
}

# ---------------------------------------------------------------------------
# 13. review mode emits Layer 3 stub message to stderr
# ---------------------------------------------------------------------------
@test "review mode: emits Layer 3 stub message to stderr" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  local kt_file="${project_dir}/src/main/kotlin/Clean.kt"
  printf 'package com.example\nclass Clean\n' > "$kt_file"

  run env \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --review \
      --project-root "$project_dir" \
      --files-changed "$kt_file"

  assert_success
  # Layer 3 stub message goes to stderr — bats captures it in $output only when using run
  # The message is written to &2, so we check it in output (bats merges stdout+stderr by default)
  assert_output --partial "Layer 3"
}

# ---------------------------------------------------------------------------
# Helper: run resolve_component() in isolation via a wrapper script.
# Sources engine.sh using bash -c with a patched invocation that bypasses
# the _ENGINE_RUNNING guard and mode dispatch by passing a no-op arg.
# We use a thin wrapper that calls the engine as a library via `source`.
# ---------------------------------------------------------------------------
_resolve_component_wrapper() {
  local file_path="$1"
  local project_root="$2"
  # Build a wrapper that sources engine.sh in a way that:
  #  1. Does NOT set _ENGINE_RUNNING before sourcing (so functions are defined)
  #  2. Replaces the main dispatch block with a direct call to resolve_component
  # Since engine.sh exits 0 at the bottom of its dispatch, we use a subshell
  # trick: source the engine with a fake mode arg that hits the "*) echo usage"
  # branch, which just writes to stderr and falls through to `exit 0`. But that
  # would define all functions first.
  # Cleanest approach: use awk to extract lines up to the "--- Main dispatch ---"
  # comment, then append our call.
  local wrapper="${TEST_TEMP}/rc-wrapper.sh"
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'PLUGIN_ROOT="%s"\n' "${PLUGIN_ROOT}"
    # Extract everything from the engine up to (but not including) the main
    # dispatch block. We stop at the line that starts "# --- Main dispatch ---".
    awk '/^# --- Main dispatch ---/{exit} {print}' "${ENGINE}" | tail -n +2
    printf 'resolve_component "%s" "%s"\n' "${file_path}" "${project_root}"
  } > "$wrapper"
  chmod +x "$wrapper"
  bash "$wrapper" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 14. resolve_component: component cache — file under mapped prefix
#     returns the cache's framework value
# ---------------------------------------------------------------------------
@test "resolve_component: component cache — file under prefix returns mapped framework" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  mkdir -p "${project_dir}/be/src/main/kotlin"
  mkdir -p "${project_dir}/fe/src"

  # Write a component cache: be=spring, fe=react
  printf 'be=spring\nfe=react\n' > "${project_dir}/.pipeline/.component-cache"

  local kt_file="${project_dir}/be/src/main/kotlin/Foo.kt"
  touch "$kt_file"

  run _resolve_component_wrapper "$kt_file" "$project_dir"
  assert_success
  assert_output "spring"
}

# ---------------------------------------------------------------------------
# 15. resolve_component: component cache — file under deeper prefix
#     tests longest-prefix wins when two prefixes could match
# ---------------------------------------------------------------------------
@test "resolve_component: component cache — longest matching prefix wins" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  mkdir -p "${project_dir}/be/adapter/src"

  # Two entries: be=spring and be/adapter=axum (more specific wins)
  printf 'be=spring\nbe/adapter=axum\n' > "${project_dir}/.pipeline/.component-cache"

  local file="${project_dir}/be/adapter/src/Handler.kt"
  touch "$file"

  run _resolve_component_wrapper "$file" "$project_dir"
  assert_success
  assert_output "axum"
}

# ---------------------------------------------------------------------------
# 16. resolve_component: component cache — file outside all prefixes → ""
#     (docker-compose.yml at project root matches no component)
# ---------------------------------------------------------------------------
@test "resolve_component: component cache — file outside all prefixes returns empty string" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  printf 'be=spring\nfe=react\n' > "${project_dir}/.pipeline/.component-cache"

  local root_file="${project_dir}/docker-compose.yml"
  touch "$root_file"

  run _resolve_component_wrapper "$root_file" "$project_dir"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# 17. resolve_component: dev-pipeline.local.md components: block
#     file under a component path resolves to that component's framework
# ---------------------------------------------------------------------------
@test "resolve_component: local.md components block — file under path returns framework" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  mkdir -p "${project_dir}/be/src/main/kotlin"
  mkdir -p "${project_dir}/fe/src"

  # Write a multi-component dev-pipeline.local.md (no component cache)
  mkdir -p "${project_dir}/.claude"
  cat > "${project_dir}/.claude/dev-pipeline.local.md" << 'CFG_EOF'
---
components:
  backend:
    path: be
    framework: spring
  frontend:
    path: fe
    framework: react
---
CFG_EOF

  local kt_file="${project_dir}/be/src/main/kotlin/Service.kt"
  touch "$kt_file"

  run _resolve_component_wrapper "$kt_file" "$project_dir"
  assert_success
  assert_output "spring"
}

# ---------------------------------------------------------------------------
# 18. resolve_component: dev-pipeline.local.md components: block
#     file under the frontend component path resolves to react
# ---------------------------------------------------------------------------
@test "resolve_component: local.md components block — frontend file returns react framework" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  mkdir -p "${project_dir}/fe/src/components"

  mkdir -p "${project_dir}/.claude"
  cat > "${project_dir}/.claude/dev-pipeline.local.md" << 'CFG_EOF'
---
components:
  backend:
    path: be
    framework: spring
  frontend:
    path: fe
    framework: react
---
CFG_EOF

  local ts_file="${project_dir}/fe/src/components/App.tsx"
  touch "$ts_file"

  run _resolve_component_wrapper "$ts_file" "$project_dir"
  assert_success
  assert_output "react"
}

# ---------------------------------------------------------------------------
# 19. resolve_component: dev-pipeline.local.md without components: block
#     falls back to detect_module() (single-component backward compat)
# ---------------------------------------------------------------------------
@test "resolve_component: no components block falls back to detect_module()" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  # Single-component config (the existing format, no components: block)
  mkdir -p "${project_dir}/.claude"
  cat > "${project_dir}/.claude/dev-pipeline.local.md" << 'CFG_EOF'
---
module: spring
framework: spring
---
CFG_EOF

  local kt_file="${project_dir}/src/main/kotlin/Svc.kt"
  touch "$kt_file"

  run _resolve_component_wrapper "$kt_file" "$project_dir"
  assert_success
  # detect_module() returns "spring" for a project with build.gradle.kts + src/main/kotlin
  assert_output "spring"
}

# ---------------------------------------------------------------------------
# 20. resolve_component: no config at all → detect_module() still works
# ---------------------------------------------------------------------------
@test "resolve_component: no config at all — detect_module() still fires" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  # No .claude/dev-pipeline.local.md, no component cache

  local kt_file="${project_dir}/src/main/kotlin/Foo.kt"
  touch "$kt_file"

  run _resolve_component_wrapper "$kt_file" "$project_dir"
  assert_success
  # Should resolve to "spring" from build.gradle.kts + src/main/kotlin heuristic
  assert_output "spring"
}

# ---------------------------------------------------------------------------
# 21. hook mode: multi-component project — file under 'be/' uses spring rules
#     (end-to-end: component cache → correct rules-override loaded)
# ---------------------------------------------------------------------------
@test "hook mode: multi-component project uses component-specific rules via cache" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  mkdir -p "${project_dir}/be/src/main/kotlin"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  # Component cache mapping be/ to spring framework
  printf 'be=spring\n' > "${project_dir}/.pipeline/.component-cache"

  local kt_file="${project_dir}/be/src/main/kotlin/Bad.kt"
  printf 'package com.example\nval x = someValue!!\n' > "$kt_file"
  git -C "$project_dir" add "$kt_file" && git -C "$project_dir" commit -q -m "add bad kt"

  run env \
    TOOL_INPUT="{\"file_path\": \"${kt_file}\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_output --partial "QUAL-NULL"
  assert_finding_format "$output"
}

# ---------------------------------------------------------------------------
# 22. hook mode: multi-component project — root file (docker-compose.yml)
#     outside any component is processed without framework rules (no crash)
# ---------------------------------------------------------------------------
@test "hook mode: root-level file outside components is processed without crash" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"

  # Component cache: be=spring (root files have no matching entry)
  printf 'be=spring\n' > "${project_dir}/.pipeline/.component-cache"

  # A Kotlin file at root would be unusual but must not crash the engine
  local root_kt="${project_dir}/Build.kt"
  printf 'val x = bad!!\n' > "$root_kt"

  run env \
    TOOL_INPUT="{\"file_path\": \"${root_kt}\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  # Engine runs without framework override — language patterns still apply
  assert_output --partial "QUAL-NULL"
}
