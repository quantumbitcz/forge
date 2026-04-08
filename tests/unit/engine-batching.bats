#!/usr/bin/env bats
# Unit tests for check engine batching — deferred hook queue and file grouping.

load '../helpers/test-helpers'

ENGINE="$PLUGIN_ROOT/shared/checks/engine.sh"

# ---------------------------------------------------------------------------
# 1. engine.sh supports batch queue references
# ---------------------------------------------------------------------------
@test "engine-batching: engine.sh contains batch/queue/deferred references" {
  run grep -cE 'batch|queue|deferred|BATCH_QUEUE|FORGE_BATCH_HOOK' "$ENGINE"
  assert_success
  [[ "$output" -gt 0 ]] || fail "No batch/queue references found in engine.sh"
}

# ---------------------------------------------------------------------------
# 2. verify mode groups files (comment or logic referencing grouping)
# ---------------------------------------------------------------------------
@test "engine-batching: verify mode references file grouping" {
  run grep -cE 'group|batch|file_groups|by_language|by_component' "$ENGINE"
  assert_success
  [[ "$output" -gt 0 ]] || fail "No grouping references found in engine.sh"
}

# ---------------------------------------------------------------------------
# 3. hook mode records to queue when FORGE_BATCH_HOOK is set
# ---------------------------------------------------------------------------
@test "engine-batching: hook mode records to queue when FORGE_BATCH_HOOK is set" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  local kt_file="${project_dir}/src/main/kotlin/Test.kt"
  printf 'package com.example\nval x = 1\n' > "$kt_file"
  local queue_file="${project_dir}/.forge/.hook-queue"
  mkdir -p "${project_dir}/.forge"

  run env \
    TOOL_INPUT="{\"file_path\": \"${kt_file}\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    FORGE_BATCH_HOOK=1 \
    FORGE_HOOK_QUEUE="$queue_file" \
    bash "$ENGINE" --hook

  assert_success
  [[ -f "$queue_file" ]] || fail "Hook queue file not created"
  grep -q "$kt_file" "$queue_file" || fail "File not added to queue"
  rm -rf "$project_dir"
}

# ---------------------------------------------------------------------------
# 4. --flush-queue processes queued files
# ---------------------------------------------------------------------------
@test "engine-batching: --flush-queue processes queued files" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  mkdir -p "${project_dir}/.forge"
  local queue_file="${project_dir}/.forge/.hook-queue"
  local kt_file="${project_dir}/src/main/kotlin/Bad.kt"
  printf 'package com.example\nval x = someValue!!\n' > "$kt_file"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"
  echo "$kt_file" > "$queue_file"

  run env \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --flush-queue --project-root "$project_dir" --queue-file "$queue_file"

  assert_success
  if [[ -f "$queue_file" ]]; then
    [[ ! -s "$queue_file" ]] || fail "Queue not cleared after flush"
  fi
  rm -rf "$project_dir"
}
