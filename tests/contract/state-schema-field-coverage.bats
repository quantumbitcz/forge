#!/usr/bin/env bats
# Contract test: fields referenced in state-transitions.md must be documented in state-schema.md.

load '../helpers/test-helpers'

@test "state-schema-coverage: evidence_refresh_count is documented in state-schema.md" {
  local schema_file="$PLUGIN_ROOT/shared/state-schema.md"
  [[ -f "$schema_file" ]] || fail "shared/state-schema.md not found"
  grep -q "evidence_refresh_count" "$schema_file" || \
    fail "evidence_refresh_count referenced in state-transitions.md but not in state-schema.md"
}

@test "state-schema-coverage: feedback_loop_count is documented in state-schema.md" {
  local schema_file="$PLUGIN_ROOT/shared/state-schema.md"
  grep -q "feedback_loop_count" "$schema_file" || \
    fail "feedback_loop_count not documented in state-schema.md"
}

@test "state-schema-coverage: convergence fields are documented in state-schema.md" {
  local schema_file="$PLUGIN_ROOT/shared/state-schema.md"
  local fields=(phase_iterations plateau_count total_iterations)
  local failures=()
  for field in "${fields[@]}"; do
    grep -q "$field" "$schema_file" || failures+=("$field")
  done
  if (( ${#failures[@]} > 0 )); then
    printf 'Missing: %s\n' "${failures[@]}"
    fail "Undocumented convergence fields: ${#failures[@]}"
  fi
}
