#!/usr/bin/env bats
# Contract tests: cost alerting, context guard, and observability integration.

load '../helpers/test-helpers'

# ── State Schema Coverage ─────────────────────────────────────────────────

@test "state-schema.md documents cost_alerting object" {
  grep -q "cost_alerting" "$PLUGIN_ROOT/shared/state-schema.md"
}

@test "state-schema.md documents context object with peak_tokens" {
  grep -qh "context.peak_tokens\|context.*peak" \
    "$PLUGIN_ROOT/shared/state-schema.md" \
    "$PLUGIN_ROOT/shared/state-schema-fields.md"
}

@test "state-schema.md documents cost.per_stage" {
  grep -qh "per_stage" \
    "$PLUGIN_ROOT/shared/state-schema.md" \
    "$PLUGIN_ROOT/shared/state-schema-fields.md"
}

@test "state-schema.md documents cost.budget_remaining_tokens" {
  grep -qh "budget_remaining_tokens" \
    "$PLUGIN_ROOT/shared/state-schema.md" \
    "$PLUGIN_ROOT/shared/state-schema-fields.md"
}

@test "state-schema.md documents tokens.by_agent dispatch_count" {
  grep -qh "dispatch_count" \
    "$PLUGIN_ROOT/shared/state-schema.md" \
    "$PLUGIN_ROOT/shared/state-schema-fields.md"
}

# ── Orchestrator Integration ──────────────────────────────────────────────

@test "orchestrator references cost-alerting.sh check before dispatch" {
  grep -q "cost-alerting.sh" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
}

@test "orchestrator references context-guard.sh check before dispatch" {
  grep -q "context-guard.sh" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
}

@test "E8 transition remains ESCALATED as safety net" {
  grep -q "E8" "$PLUGIN_ROOT/shared/state-transitions.md"
  grep -q "ESCALATED" "$PLUGIN_ROOT/shared/state-transitions.md"
}

@test "E8 row documents cost-alerting intercept pattern" {
  grep -q "cost-alerting" "$PLUGIN_ROOT/shared/state-transitions.md"
}

# ── Model Routing Cost Tracking ──────────────────────────────────────────

@test "model-routing.md references cost-per-quality-point" {
  grep -q "cost.per" "$PLUGIN_ROOT/shared/model-routing.md" || \
  grep -q "cost_per_point\|cost-per-quality\|Cost-Per-Quality" "$PLUGIN_ROOT/shared/model-routing.md"
}

@test "model-routing.md documents model_efficiency in trust.json" {
  grep -q "model_efficiency" "$PLUGIN_ROOT/shared/model-routing.md"
}

# ── Insights Dashboard ───────────────────────────────────────────────────

# Extract the `### Subcommand: insights` block from skills/forge-ask/SKILL.md.
_insights_subcommand_block() {
  awk '
    /^### Subcommand: insights$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$PLUGIN_ROOT/skills/forge-ask/SKILL.md"
}

@test "forge-ask insights Category 3 includes per-stage cost breakdown" {
  _insights_subcommand_block | grep -q "Per-Stage Cost Breakdown\|per.stage.*cost\|Per-Run Cost Trend"
}

@test "forge-ask insights Category 3 includes cost recommendations" {
  _insights_subcommand_block | grep -q "Cost Recommendation\|Top-3.*Recommendation\|recommendation"
}

@test "forge-ask insights Category 3 includes budget utilization" {
  _insights_subcommand_block | grep -q "Budget Utilization\|budget.*utilization"
}

# ── Config Validation ────────────────────────────────────────────────────

@test "cost_alerting config section documented in config-validation.md" {
  grep -q "cost_alerting" "$PLUGIN_ROOT/shared/config-validation.md"
}

@test "context_guard config section documented in config-validation.md" {
  grep -q "context_guard" "$PLUGIN_ROOT/shared/config-validation.md"
}

@test "PREFLIGHT constraints include cost_alerting" {
  grep -q "cost_alerting" "$PLUGIN_ROOT/CLAUDE.md" \
    || grep -q "cost_alerting" "$PLUGIN_ROOT/shared/preflight-constraints.md"
}

@test "PREFLIGHT constraints include context_guard" {
  grep -q "context_guard" "$PLUGIN_ROOT/CLAUDE.md" \
    || grep -q "context_guard" "$PLUGIN_ROOT/shared/preflight-constraints.md"
}
