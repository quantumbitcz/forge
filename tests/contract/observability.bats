#!/usr/bin/env bats
# Contract tests: observability.md existence, required sections, metrics, and span schema.

load '../helpers/test-helpers'

OBSERVABILITY="$PLUGIN_ROOT/shared/observability.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "observability: shared/observability.md exists" {
  [ -f "$OBSERVABILITY" ] || fail "shared/observability.md not found"
}

# ---------------------------------------------------------------------------
# 2. Required sections
# ---------------------------------------------------------------------------
@test "observability: contains ## Trace Hierarchy" {
  grep -q "^## Trace Hierarchy" "$OBSERVABILITY" \
    || fail "Missing required section: ## Trace Hierarchy"
}

@test "observability: contains ## Metrics" {
  grep -q "^## Metrics" "$OBSERVABILITY" \
    || fail "Missing required section: ## Metrics"
}

@test "observability: contains ## Configuration" {
  grep -q "^## Configuration" "$OBSERVABILITY" \
    || fail "Missing required section: ## Configuration"
}

@test "observability: contains ## Export Modes" {
  grep -q "^## Export Modes" "$OBSERVABILITY" \
    || fail "Missing required section: ## Export Modes"
}

@test "observability: contains ## Span Schema" {
  grep -q "^## Span Schema" "$OBSERVABILITY" \
    || fail "Missing required section: ## Span Schema"
}

@test "observability: contains ## State Schema" {
  grep -q "^## State Schema" "$OBSERVABILITY" \
    || fail "Missing required section: ## State Schema"
}

@test "observability: contains ## PREFLIGHT Constraints" {
  grep -q "^## PREFLIGHT Constraints" "$OBSERVABILITY" \
    || fail "Missing required section: ## PREFLIGHT Constraints"
}

# ---------------------------------------------------------------------------
# 3. All 9 metrics defined
# ---------------------------------------------------------------------------
@test "observability: defines forge.stage.duration_seconds metric" {
  grep -q "forge\.stage\.duration_seconds" "$OBSERVABILITY" \
    || fail "Missing metric: forge.stage.duration_seconds"
}

@test "observability: defines forge.agent.duration_seconds metric" {
  grep -q "forge\.agent\.duration_seconds" "$OBSERVABILITY" \
    || fail "Missing metric: forge.agent.duration_seconds"
}

@test "observability: defines forge.agent.tokens.input metric" {
  grep -q "forge\.agent\.tokens\.input" "$OBSERVABILITY" \
    || fail "Missing metric: forge.agent.tokens.input"
}

@test "observability: defines forge.agent.tokens.output metric" {
  grep -q "forge\.agent\.tokens\.output" "$OBSERVABILITY" \
    || fail "Missing metric: forge.agent.tokens.output"
}

@test "observability: defines forge.convergence.iterations metric" {
  grep -q "forge\.convergence\.iterations" "$OBSERVABILITY" \
    || fail "Missing metric: forge.convergence.iterations"
}

@test "observability: defines forge.score metric" {
  grep -q "forge\.score" "$OBSERVABILITY" \
    || fail "Missing metric: forge.score"
}

@test "observability: defines forge.findings.count metric" {
  grep -q "forge\.findings\.count" "$OBSERVABILITY" \
    || fail "Missing metric: forge.findings.count"
}

@test "observability: defines forge.recovery.budget_used metric" {
  grep -q "forge\.recovery\.budget_used" "$OBSERVABILITY" \
    || fail "Missing metric: forge.recovery.budget_used"
}

@test "observability: defines forge.model.distribution metric" {
  grep -q "forge\.model\.distribution" "$OBSERVABILITY" \
    || fail "Missing metric: forge.model.distribution"
}

# ---------------------------------------------------------------------------
# 4. Span schema fields
# ---------------------------------------------------------------------------
@test "observability: span schema includes name field" {
  grep -q '| `name`' "$OBSERVABILITY" \
    || fail "Span schema missing 'name' field"
}

@test "observability: span schema includes type field" {
  grep -q '| `type`' "$OBSERVABILITY" \
    || fail "Span schema missing 'type' field"
}

@test "observability: span schema includes start field" {
  grep -q '| `start`' "$OBSERVABILITY" \
    || fail "Span schema missing 'start' field"
}

@test "observability: span schema includes end field" {
  grep -q '| `end`' "$OBSERVABILITY" \
    || fail "Span schema missing 'end' field"
}

@test "observability: span schema includes agent field" {
  grep -q '| `agent`' "$OBSERVABILITY" \
    || fail "Span schema missing 'agent' field"
}

@test "observability: span schema includes model field" {
  grep -q '| `model`' "$OBSERVABILITY" \
    || fail "Span schema missing 'model' field"
}

@test "observability: span schema includes tokens_in field" {
  grep -q '| `tokens_in`' "$OBSERVABILITY" \
    || fail "Span schema missing 'tokens_in' field"
}

@test "observability: span schema includes tokens_out field" {
  grep -q '| `tokens_out`' "$OBSERVABILITY" \
    || fail "Span schema missing 'tokens_out' field"
}

@test "observability: span schema includes findings_count field" {
  grep -q '| `findings_count`' "$OBSERVABILITY" \
    || fail "Span schema missing 'findings_count' field"
}

# ---------------------------------------------------------------------------
# 5. Span types documented
# ---------------------------------------------------------------------------
@test "observability: documents all four span types" {
  grep -q "pipeline" "$OBSERVABILITY" || fail "Span type 'pipeline' not documented"
  grep -q "stage" "$OBSERVABILITY" || fail "Span type 'stage' not documented"
  grep -q "agent" "$OBSERVABILITY" || fail "Span type 'agent' not documented"
  grep -q "batch" "$OBSERVABILITY" || fail "Span type 'batch' not documented"
}

# ---------------------------------------------------------------------------
# 6. Export modes documented
# ---------------------------------------------------------------------------
@test "observability: documents local export mode" {
  grep -q "### Local" "$OBSERVABILITY" \
    || fail "Local export mode not documented"
}

@test "observability: documents otel export mode" {
  grep -q "### OTel" "$OBSERVABILITY" \
    || fail "OTel export mode not documented"
}

# ---------------------------------------------------------------------------
# 7. Export status enum values
# ---------------------------------------------------------------------------
@test "observability: defines export_status enum values" {
  grep -q "pending" "$OBSERVABILITY" || fail "export_status value 'pending' not defined"
  grep -q "exported" "$OBSERVABILITY" || fail "export_status value 'exported' not defined"
  grep -q "failed" "$OBSERVABILITY" || fail "export_status value 'failed' not defined"
}
