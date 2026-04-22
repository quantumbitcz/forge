#!/usr/bin/env bats
# Contract tests: shared/state-schema.md — validates the state schema document.

load '../helpers/test-helpers'

STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
STATE_SCHEMA_FIELDS="$PLUGIN_ROOT/shared/state-schema-fields.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "state-schema: document exists" {
  [[ -f "$STATE_SCHEMA" ]]
}

# ---------------------------------------------------------------------------
# 2. Schema version is "1.10.0" (bumped from 1.9.0 for session-handoff tracking)
# ---------------------------------------------------------------------------
@test "state-schema: schema version 1.10.0 documented" {
  grep -q '"version": "1.10.0"' "$STATE_SCHEMA" \
    || fail 'Schema version "1.10.0" not found in state-schema.md'
}

# ---------------------------------------------------------------------------
# 2b. Self-consistency voting counters (still present in schema 1.10.0)
# ---------------------------------------------------------------------------
@test "state-schema 1.10.0 declares consistency_cache_hits and consistency_votes" {
  grep -Eq '"consistency_cache_hits"[[:space:]]*:[[:space:]]*0' "$STATE_SCHEMA" \
    || fail "consistency_cache_hits field not found in state-schema.md"

  grep -Eq '"consistency_votes"[[:space:]]*:' "$STATE_SCHEMA" \
    || fail "consistency_votes object not found in state-schema.md"

  grep -Eq '1\.9\.0[[:space:]]*\|[[:space:]]*1\.10\.0' "$STATE_SCHEMA_FIELDS" \
    || fail "1.9.0 -> 1.10.0 migration row not found in state-schema-fields.md (migration table lives there per state-schema.md §Atomic writes)"
}

# ---------------------------------------------------------------------------
# 3. Required fields documented
# ---------------------------------------------------------------------------
@test "state-schema: required fields documented (version complete story_id story_state components active_component total_retries total_retries_max)" {
  local fields=(version complete story_id story_state components active_component total_retries total_retries_max)
  for field in "${fields[@]}"; do
    grep -q "\"${field}\"\|${field}" "$STATE_SCHEMA" \
      || fail "Required field $field not found in state-schema.md"
  done
}

# ---------------------------------------------------------------------------
# 3b. Tracking fields documented
# ---------------------------------------------------------------------------
@test "state-schema: tracking fields ticket_id branch_name tracking_dir documented" {
  for field in ticket_id branch_name tracking_dir; do
    grep -q "$field" "$STATE_SCHEMA" \
      || fail "Tracking field $field not found in state-schema.md"
  done
}

# ---------------------------------------------------------------------------
# 4. risk_level valid values documented: LOW, MEDIUM, HIGH
# ---------------------------------------------------------------------------
@test "state-schema: risk_level valid values LOW MEDIUM HIGH documented" {
  grep -qh "risk_level" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" || fail "risk_level field not found"
  grep -qh '"LOW"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"      || fail 'risk_level value "LOW" not found'
  grep -qh '"MEDIUM"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"   || fail 'risk_level value "MEDIUM" not found'
  grep -qh '"HIGH"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"     || fail 'risk_level value "HIGH" not found'
}

# ---------------------------------------------------------------------------
# 5. integrations object documented with: linear, playwright, slack, context7, figma
# ---------------------------------------------------------------------------
@test "state-schema: integrations object documented with all 5 integration keys" {
  grep -q '"integrations"' "$STATE_SCHEMA" || fail "integrations object not found"
  local keys=(linear playwright slack context7 figma)
  for key in "${keys[@]}"; do
    grep -q "\"${key}\"" "$STATE_SCHEMA" \
      || fail "Integration key $key not found in state-schema.md"
  done
}

# ---------------------------------------------------------------------------
# 6. recovery_budget structure documented: total_weight, max_weight, applications[]
# ---------------------------------------------------------------------------
@test "state-schema: recovery_budget structure documented with total_weight max_weight applications" {
  grep -q "recovery_budget" "$STATE_SCHEMA" || fail "recovery_budget not found"
  grep -q "total_weight"    "$STATE_SCHEMA" || fail "total_weight not found"
  grep -q "max_weight"      "$STATE_SCHEMA" || fail "max_weight not found"
  grep -q "applications"    "$STATE_SCHEMA" || fail "applications array not found"
}

# ---------------------------------------------------------------------------
# 7. detected_versions structure documented: language_version, framework_version
# ---------------------------------------------------------------------------
@test "state-schema: detected_versions documented with language_version and framework_version" {
  grep -q "detected_versions" "$STATE_SCHEMA"  || fail "detected_versions not found"
  grep -q "language_version"  "$STATE_SCHEMA"  || fail "language_version not found"
  grep -q "framework_version" "$STATE_SCHEMA"  || fail "framework_version not found"
}

# ---------------------------------------------------------------------------
# 8. total_retries_max constraint: >= 5 and <= 30
# ---------------------------------------------------------------------------
@test "state-schema: total_retries_max constraint >= 5 and <= 30 documented" {
  grep -qh "total_retries_max" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" || fail "total_retries_max not found"
  grep -qh ">= 5" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"  || fail "total_retries_max lower bound >= 5 not found"
  grep -qh "<= 30" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" || fail "total_retries_max upper bound <= 30 not found"
}

# ---------------------------------------------------------------------------
# 9. v1.0.0 clean break documented: forge-recover required
# ---------------------------------------------------------------------------
@test "state-schema: v1.0.0 clean break and forge-recover documented" {
  grep -q "clean break\|forge-recover\|incompatible" "$STATE_SCHEMA" \
    || fail "v1.0.0 clean break / forge-recover guidance not documented"
}

# ---------------------------------------------------------------------------
# 9b. components and active_component fields documented
# ---------------------------------------------------------------------------
@test "state-schema: components and active_component fields documented" {
  grep -q '"components"' "$STATE_SCHEMA" \
    || fail '"components" field not found in state-schema.md'
  grep -q '"active_component"' "$STATE_SCHEMA" \
    || fail '"active_component" field not found in state-schema.md'
  grep -q "conventions_hash\|conventions_section_hashes" "$STATE_SCHEMA" \
    || fail "component conventions_hash fields not documented"
}

# ---------------------------------------------------------------------------
# 10. Checkpoint schema documented (checkpoint-{storyId}.json)
# ---------------------------------------------------------------------------
@test "state-schema: checkpoint schema documented with checkpoint-storyId.json naming" {
  grep -q "checkpoint-{storyId}\|checkpoint-.*storyId\|checkpoint-\*\.json\|checkpoint-" "$STATE_SCHEMA" \
    || fail "checkpoint-{storyId}.json naming not documented"
  grep -q "storyId\|story_id" "$STATE_SCHEMA" \
    || fail "storyId field for checkpoint not documented"
}

# ---------------------------------------------------------------------------
# convergence object documented in state schema
# ---------------------------------------------------------------------------
@test "state-schema: convergence object documented" {
  grep -q '"convergence"' "$STATE_SCHEMA" \
    || fail "convergence object not found in state schema"
}

# ---------------------------------------------------------------------------
# convergence required fields documented
# ---------------------------------------------------------------------------
@test "state-schema: convergence fields documented (phase phase_iterations total_iterations plateau_count convergence_state safety_gate_passed safety_gate_failures unfixable_findings)" {
  local fields=(phase phase_iterations total_iterations plateau_count convergence_state safety_gate_passed safety_gate_failures unfixable_findings)
  for field in "${fields[@]}"; do
    grep -qh "convergence\.${field}\|convergence.*${field}" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" \
      || fail "convergence field $field not documented in state-schema(-fields).md"
  done
}

# ---------------------------------------------------------------------------
# convergence phase valid values documented
# ---------------------------------------------------------------------------
@test "state-schema: convergence phase valid values correctness perfection safety_gate documented" {
  grep -qh '"correctness"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" || fail 'convergence phase "correctness" not documented'
  grep -qh '"perfection"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"  || fail 'convergence phase "perfection" not documented'
  grep -qh '"safety_gate"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" || fail 'convergence phase "safety_gate" not documented'
}

# ---------------------------------------------------------------------------
# convergence phase_history outcome values documented
# ---------------------------------------------------------------------------
@test "state-schema: phase_history outcome values converged escalated restarted documented" {
  grep -qh '"converged"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"  || fail 'phase_history outcome "converged" not documented'
  grep -qh '"escalated"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"  || fail 'phase_history outcome "escalated" not documented'
  grep -qh '"restarted"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"  || fail 'phase_history outcome "restarted" not documented'
}

# ---------------------------------------------------------------------------
# new state fields from iteration 1 fixes documented
# ---------------------------------------------------------------------------
@test "state-schema: exploration_degraded field documented" {
  grep -qh "exploration_degraded" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" || fail "exploration_degraded not documented"
}

@test "state-schema: documentation.generation_error field documented" {
  grep -qh "generation_error" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" || fail "documentation.generation_error not documented"
}

@test "state-schema: last_score_delta typed as number not integer" {
  grep -h "last_score_delta" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" | grep -q "number" || fail "last_score_delta should be typed as number (not integer)"
}

# ---------------------------------------------------------------------------
# v1.0.0 fixture validation
# ---------------------------------------------------------------------------
@test "state-schema: v1.0.0 fixture is valid JSON with correct version" {
  local fixture="$PLUGIN_ROOT/tests/fixtures/state/v1.0.0-valid.json"
  [[ -f "$fixture" ]] || fail "v1.0.0 fixture not found"
  jq -e '.version == "1.0.0"' "$fixture" >/dev/null || fail "v1.0.0 fixture has wrong version"
}

@test "state-schema: v1.0.0 fixture has all required top-level fields" {
  local fixture="$PLUGIN_ROOT/tests/fixtures/state/v1.0.0-valid.json"
  local fields=(version complete story_id story_state components active_component total_retries total_retries_max mode convergence)
  for field in "${fields[@]}"; do
    jq -e "has(\"$field\")" "$fixture" >/dev/null || fail "v1.0.0 fixture missing required field: $field"
  done
}

@test "state-schema: v1.0.0 fixture has feedback loop fields" {
  local fixture="$PLUGIN_ROOT/tests/fixtures/state/v1.0.0-valid.json"
  jq -e 'has("feedback_classification")' "$fixture" >/dev/null \
    || fail "v1.0.0 fixture missing feedback_classification"
  jq -e 'has("previous_feedback_classification")' "$fixture" >/dev/null \
    || fail "v1.0.0 fixture missing previous_feedback_classification"
  jq -e 'has("feedback_loop_count")' "$fixture" >/dev/null \
    || fail "v1.0.0 fixture missing feedback_loop_count"
}

@test "state-schema: v1.0.0 fixture has proper integrations object structure" {
  local fixture="$PLUGIN_ROOT/tests/fixtures/state/v1.0.0-valid.json"
  jq -e '.integrations.linear | has("available")' "$fixture" >/dev/null \
    || fail "integrations.linear missing .available field (stale boolean schema?)"
  jq -e '.integrations.neo4j | has("available")' "$fixture" >/dev/null \
    || fail "integrations.neo4j missing .available field"
}

@test "state-schema: previous_feedback_classification documented" {
  grep -q "previous_feedback_classification" "$PLUGIN_ROOT/shared/state-schema.md" \
    || fail "previous_feedback_classification not documented in state-schema.md"
}

@test "state-schema: bootstrap mode documented" {
  grep -qh '"bootstrap"' "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" \
    || fail "bootstrap mode value not documented in state-schema(-fields).md"
}
