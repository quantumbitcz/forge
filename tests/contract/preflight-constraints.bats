#!/usr/bin/env bats
# Contract tests: PREFLIGHT constraint validation for all configurable parameters.
# Ensures stage-contract.md and CLAUDE.md document validation ranges for
# sprint, tracking, scoring, and convergence parameters.

load '../helpers/test-helpers'

STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
PREFLIGHT_CONSTRAINTS="$PLUGIN_ROOT/shared/preflight-constraints.md"
SPRINT_SCHEMA="$PLUGIN_ROOT/shared/sprint-state-schema.md"
TRACKING_SCHEMA="$PLUGIN_ROOT/shared/tracking/tracking-schema.md"
RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"

# ---------------------------------------------------------------------------
# 1. Sprint params documented in stage-contract.md PREFLIGHT
# ---------------------------------------------------------------------------
@test "preflight-constraints: sprint.poll_interval_seconds range in stage-contract" {
  grep -q "poll_interval_seconds.*10.*120" "$STAGE_CONTRACT" \
    || fail "sprint.poll_interval_seconds range not in stage-contract.md PREFLIGHT"
}

@test "preflight-constraints: sprint.dependency_timeout_minutes range in stage-contract" {
  grep -q "dependency_timeout_minutes.*5.*180" "$STAGE_CONTRACT" \
    || fail "sprint.dependency_timeout_minutes range not in stage-contract.md PREFLIGHT"
}

# ---------------------------------------------------------------------------
# 2. Tracking params documented in stage-contract.md PREFLIGHT
# ---------------------------------------------------------------------------
@test "preflight-constraints: tracking.archive_after_days range in stage-contract" {
  grep -q "archive_after_days" "$STAGE_CONTRACT" \
    || fail "tracking.archive_after_days not in stage-contract.md PREFLIGHT"
}

# ---------------------------------------------------------------------------
# 3. Sprint params in CLAUDE.md PREFLIGHT constraints
# ---------------------------------------------------------------------------
@test "preflight-constraints: sprint constraints documented" {
  grep -q "sprint.*poll_interval_seconds" "$CLAUDE_MD" \
    || grep -q "sprint.*poll_interval_seconds" "$PREFLIGHT_CONSTRAINTS" \
    || fail "sprint.poll_interval_seconds not in CLAUDE.md or preflight-constraints.md"
}

@test "preflight-constraints: tracking constraints documented" {
  grep -q "tracking.*archive_after_days" "$CLAUDE_MD" \
    || grep -q "tracking.*archive_after_days" "$PREFLIGHT_CONSTRAINTS" \
    || fail "tracking.archive_after_days not in CLAUDE.md or preflight-constraints.md"
}

# ---------------------------------------------------------------------------
# 4. Sprint polling documented in sprint-state-schema
# ---------------------------------------------------------------------------
@test "preflight-constraints: sprint polling interval documented in sprint-state-schema" {
  grep -q "poll_interval_seconds" "$SPRINT_SCHEMA" \
    || fail "poll_interval_seconds not in sprint-state-schema.md"
}

@test "preflight-constraints: dependency timeout consistent across sprint-state-schema" {
  grep -q "dependency_timeout_minutes" "$SPRINT_SCHEMA" \
    || fail "dependency_timeout_minutes not in sprint-state-schema.md"
}

# ---------------------------------------------------------------------------
# 5. Ticket archival documented in tracking schema
# ---------------------------------------------------------------------------
@test "preflight-constraints: archival policy in tracking-schema" {
  grep -q "archive_after_days\|Archival\|archival" "$TRACKING_SCHEMA" \
    || fail "Archival policy not in tracking-schema.md"
}

# ---------------------------------------------------------------------------
# 6. Recovery budget reset documented
# ---------------------------------------------------------------------------
@test "preflight-constraints: recovery budget reset at PREFLIGHT documented" {
  grep -q "resets.*PREFLIGHT\|reset.*PREFLIGHT\|Budget Reset" "$RECOVERY_ENGINE" \
    || fail "Recovery budget reset at PREFLIGHT not documented in recovery-engine.md"
}

@test "preflight-constraints: sprint mode budget scope documented" {
  grep -q "Sprint Mode Budget\|per-feature.*budget\|independent.*budget" "$RECOVERY_ENGINE" \
    || fail "Sprint mode budget scope not documented in recovery-engine.md"
}

# ---------------------------------------------------------------------------
# 7. Config templates include sprint/tracking params
# ---------------------------------------------------------------------------
@test "preflight-constraints: all framework config templates have sprint params" {
  local missing=0
  for template in "$PLUGIN_ROOT"/modules/frameworks/*/forge-config-template.md; do
    if ! grep -q "poll_interval_seconds" "$template"; then
      echo "MISSING sprint params: $(basename "$(dirname "$template")")" >&2
      missing=$((missing + 1))
    fi
  done
  [[ "$missing" -eq 0 ]] || fail "$missing framework templates missing sprint params"
}

@test "preflight-constraints: all framework local templates have tracking archive param" {
  local missing=0
  for template in "$PLUGIN_ROOT"/modules/frameworks/*/local-template.md; do
    if ! grep -q "archive_after_days" "$template"; then
      echo "MISSING tracking params: $(basename "$(dirname "$template")")" >&2
      missing=$((missing + 1))
    fi
  done
  [[ "$missing" -eq 0 ]] || fail "$missing framework local templates missing tracking archive param"
}

# ---------------------------------------------------------------------------
# compression_eval config documented in CLAUDE.md
# ---------------------------------------------------------------------------
@test "preflight-constraints: compression_eval params documented" {
  grep -q "compression_eval.enabled" "$CLAUDE_MD" \
    || grep -q "compression_eval.enabled" "$PREFLIGHT_CONSTRAINTS" \
    || fail "compression_eval.enabled not in CLAUDE.md or preflight-constraints.md"
  grep -q "compression_eval.drift_threshold_pct" "$CLAUDE_MD" \
    || grep -q "compression_eval.drift_threshold_pct" "$PREFLIGHT_CONSTRAINTS" \
    || fail "compression_eval.drift_threshold_pct not in CLAUDE.md or preflight-constraints.md"
}

@test "preflight-constraints: config schema includes compression_eval" {
  grep -q '"compression_eval"' "$PLUGIN_ROOT/shared/config-schema.json" \
    || fail "compression_eval not in config-schema.json"
}
