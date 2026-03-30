#!/usr/bin/env bats
# Contract tests: shared/state-schema.md — validates the state schema document.

load '../helpers/test-helpers'

STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "state-schema: document exists" {
  [[ -f "$STATE_SCHEMA" ]]
}

# ---------------------------------------------------------------------------
# 2. Schema version is "2.0.0"
# ---------------------------------------------------------------------------
@test "state-schema: schema version 2.0.0 documented" {
  grep -q '"version": "2.0.0"' "$STATE_SCHEMA" \
    || fail 'Schema version "2.0.0" not found in state-schema.md'
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
# 4. risk_level valid values documented: LOW, MEDIUM, HIGH
# ---------------------------------------------------------------------------
@test "state-schema: risk_level valid values LOW MEDIUM HIGH documented" {
  grep -q "risk_level" "$STATE_SCHEMA" || fail "risk_level field not found"
  grep -q '"LOW"' "$STATE_SCHEMA"      || fail 'risk_level value "LOW" not found'
  grep -q '"MEDIUM"' "$STATE_SCHEMA"   || fail 'risk_level value "MEDIUM" not found'
  grep -q '"HIGH"' "$STATE_SCHEMA"     || fail 'risk_level value "HIGH" not found'
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
  grep -q "total_retries_max" "$STATE_SCHEMA" || fail "total_retries_max not found"
  grep -q ">= 5" "$STATE_SCHEMA"  || fail "total_retries_max lower bound >= 5 not found"
  grep -q "<= 30" "$STATE_SCHEMA" || fail "total_retries_max upper bound <= 30 not found"
}

# ---------------------------------------------------------------------------
# 9. v1.0.0 clean break documented: pipeline-reset required
# ---------------------------------------------------------------------------
@test "state-schema: v1.0.0 clean break and pipeline-reset documented" {
  grep -q "clean break\|pipeline-reset\|incompatible" "$STATE_SCHEMA" \
    || fail "v1.0.0 clean break / pipeline-reset guidance not documented"
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
@test "state-schema: convergence fields documented (phase phase_iterations total_iterations plateau_count convergence_state safety_gate_passed unfixable_findings)" {
  local fields=(phase phase_iterations total_iterations plateau_count convergence_state safety_gate_passed unfixable_findings)
  for field in "${fields[@]}"; do
    grep -q "convergence\.${field}\|convergence.*${field}" "$STATE_SCHEMA" \
      || fail "convergence field $field not documented in state-schema.md"
  done
}

# ---------------------------------------------------------------------------
# convergence phase valid values documented
# ---------------------------------------------------------------------------
@test "state-schema: convergence phase valid values correctness perfection safety_gate documented" {
  grep -q '"correctness"' "$STATE_SCHEMA" || fail 'convergence phase "correctness" not documented'
  grep -q '"perfection"' "$STATE_SCHEMA"  || fail 'convergence phase "perfection" not documented'
  grep -q '"safety_gate"' "$STATE_SCHEMA" || fail 'convergence phase "safety_gate" not documented'
}
