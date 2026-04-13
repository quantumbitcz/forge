#!/usr/bin/env bats
# Contract tests: shared/background-execution.md existence and required sections.

load '../helpers/test-helpers'

BG_EXEC="$PLUGIN_ROOT/shared/background-execution.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "background-execution: shared/background-execution.md exists" {
  [ -f "$BG_EXEC" ] || fail "shared/background-execution.md not found"
}

# ---------------------------------------------------------------------------
# 2. Required sections — Progress Artifacts
# ---------------------------------------------------------------------------
@test "background-execution: contains ## Progress Artifacts" {
  grep -q "^## Progress Artifacts" "$BG_EXEC" \
    || fail "Missing required section: ## Progress Artifacts"
}

# ---------------------------------------------------------------------------
# 3. Required sections — Status Schema
# ---------------------------------------------------------------------------
@test "background-execution: contains Status Schema section" {
  grep -q "Status Schema\|### status.json" "$BG_EXEC" \
    || fail "Missing required section: Status Schema or ### status.json"
}

# ---------------------------------------------------------------------------
# 4. Required sections — Escalation Behavior
# ---------------------------------------------------------------------------
@test "background-execution: contains ## Escalation Behavior" {
  grep -q "^## Escalation Behavior" "$BG_EXEC" \
    || fail "Missing required section: ## Escalation Behavior"
}

# ---------------------------------------------------------------------------
# 5. Required sections — Configuration
# ---------------------------------------------------------------------------
@test "background-execution: contains ## Configuration" {
  grep -q "^## Configuration" "$BG_EXEC" \
    || fail "Missing required section: ## Configuration"
}

# ---------------------------------------------------------------------------
# 6. Progress artifact files documented
# ---------------------------------------------------------------------------
@test "background-execution: documents status.json artifact" {
  grep -q "status.json" "$BG_EXEC" \
    || fail "status.json artifact not documented"
}

@test "background-execution: documents timeline.jsonl artifact" {
  grep -q "timeline.jsonl" "$BG_EXEC" \
    || fail "timeline.jsonl artifact not documented"
}

@test "background-execution: documents stage-summary directory" {
  grep -q "stage-summary" "$BG_EXEC" \
    || fail "stage-summary directory not documented"
}

@test "background-execution: documents alerts.json artifact" {
  grep -q "alerts.json" "$BG_EXEC" \
    || fail "alerts.json artifact not documented"
}

# ---------------------------------------------------------------------------
# 7. status.json schema fields documented
# ---------------------------------------------------------------------------
@test "background-execution: status schema includes run_id" {
  grep -q "run_id" "$BG_EXEC" \
    || fail "run_id not in status schema"
}

@test "background-execution: status schema includes stage" {
  grep -q '"stage"' "$BG_EXEC" \
    || fail "stage not in status schema"
}

@test "background-execution: status schema includes stage_number" {
  grep -q "stage_number" "$BG_EXEC" \
    || fail "stage_number not in status schema"
}

@test "background-execution: status schema includes progress_pct" {
  grep -q "progress_pct" "$BG_EXEC" \
    || fail "progress_pct not in status schema"
}

@test "background-execution: status schema includes score" {
  grep -q '"score"' "$BG_EXEC" \
    || fail "score not in status schema"
}

@test "background-execution: status schema includes convergence_phase" {
  grep -q "convergence_phase" "$BG_EXEC" \
    || fail "convergence_phase not in status schema"
}

@test "background-execution: status schema includes convergence_iteration" {
  grep -q "convergence_iteration" "$BG_EXEC" \
    || fail "convergence_iteration not in status schema"
}

@test "background-execution: status schema includes started_at" {
  grep -q "started_at" "$BG_EXEC" \
    || fail "started_at not in status schema"
}

@test "background-execution: status schema includes last_update" {
  grep -q "last_update" "$BG_EXEC" \
    || fail "last_update not in status schema"
}

@test "background-execution: status schema includes alerts array" {
  grep -q '"alerts"' "$BG_EXEC" \
    || fail "alerts array not in status schema"
}

@test "background-execution: status schema includes model_usage" {
  grep -q "model_usage" "$BG_EXEC" \
    || fail "model_usage not in status schema"
}

# ---------------------------------------------------------------------------
# 8. Alert types documented
# ---------------------------------------------------------------------------
@test "background-execution: documents REGRESSING alert type" {
  grep -q "REGRESSING" "$BG_EXEC" \
    || fail "REGRESSING alert type not documented"
}

@test "background-execution: documents CONCERNS alert type" {
  grep -q "CONCERNS" "$BG_EXEC" \
    || fail "CONCERNS alert type not documented"
}

@test "background-execution: documents UNRECOVERABLE_CRITICAL alert type" {
  grep -q "UNRECOVERABLE_CRITICAL" "$BG_EXEC" \
    || fail "UNRECOVERABLE_CRITICAL alert type not documented"
}

# ---------------------------------------------------------------------------
# 9. Escalation pause behavior documented
# ---------------------------------------------------------------------------
@test "background-execution: documents pipeline pause on escalation" {
  grep -qi "pause" "$BG_EXEC" \
    || fail "Pipeline pause behavior not documented"
}

@test "background-execution: documents alert resolution mechanism" {
  grep -q "resolved" "$BG_EXEC" \
    || fail "Alert resolution mechanism not documented"
}

# ---------------------------------------------------------------------------
# 10. Activation documented
# ---------------------------------------------------------------------------
@test "background-execution: documents --background flag" {
  grep -q "\-\-background" "$BG_EXEC" \
    || fail "--background flag not documented"
}

# ---------------------------------------------------------------------------
# 11. Configuration parameters documented
# ---------------------------------------------------------------------------
@test "background-execution: documents alert_timeout_minutes parameter" {
  grep -q "alert_timeout_minutes" "$BG_EXEC" \
    || fail "alert_timeout_minutes parameter not documented"
}

@test "background-execution: documents poll_interval_seconds parameter" {
  grep -q "poll_interval_seconds" "$BG_EXEC" \
    || fail "poll_interval_seconds parameter not documented"
}

@test "background-execution: documents slack_notifications parameter" {
  grep -q "slack_notifications" "$BG_EXEC" \
    || fail "slack_notifications parameter not documented"
}

# ---------------------------------------------------------------------------
# 12. User interaction documented
# ---------------------------------------------------------------------------
@test "background-execution: documents /forge-status integration" {
  grep -q "/forge-status" "$BG_EXEC" \
    || fail "/forge-status integration not documented"
}

@test "background-execution: documents --watch polling" {
  grep -q "\-\-watch" "$BG_EXEC" \
    || fail "--watch polling not documented"
}

@test "background-execution: documents Slack notification when MCP available" {
  grep -q "Slack" "$BG_EXEC" \
    || fail "Slack notification not documented"
}

# ---------------------------------------------------------------------------
# 13. Timeline event types documented
# ---------------------------------------------------------------------------
@test "background-execution: documents timeline event types" {
  for event in pipeline_start pipeline_end stage_enter stage_exit agent_dispatch score_update alert; do
    grep -q "$event" "$BG_EXEC" \
      || fail "Timeline event type '$event' not documented"
  done
}

# ---------------------------------------------------------------------------
# 14. Orchestrator behavior section
# ---------------------------------------------------------------------------
@test "background-execution: contains ## Orchestrator Behavior" {
  grep -q "^## Orchestrator Behavior" "$BG_EXEC" \
    || fail "Missing required section: ## Orchestrator Behavior"
}

# ---------------------------------------------------------------------------
# 15. .forge/progress/ directory path documented
# ---------------------------------------------------------------------------
@test "background-execution: documents .forge/progress/ directory" {
  grep -q ".forge/progress/" "$BG_EXEC" \
    || fail ".forge/progress/ directory not documented"
}
