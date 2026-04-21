#!/usr/bin/env bats
# Contract tests: observability.md existence, required sections, semconv
# attributes, and span-name cardinality budget. Tracks the OTel GenAI
# Semantic Conventions (2026) contract.

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
@test "observability: contains ## Durability contract" {
  grep -q "^## Durability contract" "$OBSERVABILITY" \
    || fail "Missing required section: ## Durability contract"
}

@test "observability: contains ## Sampler" {
  grep -q "^## Sampler" "$OBSERVABILITY" \
    || fail "Missing required section: ## Sampler"
}

@test "observability: contains ## Trace-context propagation" {
  grep -q "^## Trace-context propagation" "$OBSERVABILITY" \
    || fail "Missing required section: ## Trace-context propagation"
}

@test "observability: contains ## Attributes" {
  grep -q "^## Attributes" "$OBSERVABILITY" \
    || fail "Missing required section: ## Attributes"
}

@test "observability: contains ## Cardinality budget" {
  grep -q "^## Cardinality budget" "$OBSERVABILITY" \
    || fail "Missing required section: ## Cardinality budget"
}

@test "observability: contains ## Configuration" {
  grep -q "^## Configuration" "$OBSERVABILITY" \
    || fail "Missing required section: ## Configuration"
}

@test "observability: contains ## OpenInference compatibility" {
  grep -q "^## OpenInference compatibility" "$OBSERVABILITY" \
    || fail "Missing required section: ## OpenInference compatibility"
}

@test "observability: contains ## Migration from forge-otel-export.sh" {
  grep -q "^## Migration from \`forge-otel-export.sh\`" "$OBSERVABILITY" \
    || fail "Missing required section: ## Migration from forge-otel-export.sh"
}

# ---------------------------------------------------------------------------
# 3. Semconv agent-span attributes
# ---------------------------------------------------------------------------
@test "observability: documents gen_ai.agent.name attribute" {
  grep -q "gen_ai\.agent\.name" "$OBSERVABILITY" \
    || fail "Missing semconv attribute: gen_ai.agent.name"
}

@test "observability: documents gen_ai.request.model attribute" {
  grep -q "gen_ai\.request\.model" "$OBSERVABILITY" \
    || fail "Missing semconv attribute: gen_ai.request.model"
}

@test "observability: documents gen_ai.tokens.input attribute" {
  grep -q "gen_ai\.tokens\.input" "$OBSERVABILITY" \
    || fail "Missing semconv attribute: gen_ai.tokens.input"
}

@test "observability: documents gen_ai.tokens.output attribute" {
  grep -q "gen_ai\.tokens\.output" "$OBSERVABILITY" \
    || fail "Missing semconv attribute: gen_ai.tokens.output"
}

@test "observability: documents gen_ai.tokens.total attribute" {
  grep -q "gen_ai\.tokens\.total" "$OBSERVABILITY" \
    || fail "Missing semconv attribute: gen_ai.tokens.total"
}

@test "observability: documents gen_ai.cost.usd attribute" {
  grep -q "gen_ai\.cost\.usd" "$OBSERVABILITY" \
    || fail "Missing semconv attribute: gen_ai.cost.usd"
}

@test "observability: documents gen_ai.tool.calls attribute" {
  grep -q "gen_ai\.tool\.calls" "$OBSERVABILITY" \
    || fail "Missing semconv attribute: gen_ai.tool.calls"
}

# ---------------------------------------------------------------------------
# 4. Forge-specific pipeline/stage attributes
# ---------------------------------------------------------------------------
@test "observability: documents forge.run_id attribute" {
  grep -q "forge\.run_id" "$OBSERVABILITY" \
    || fail "Missing forge attribute: forge.run_id"
}

@test "observability: documents forge.stage attribute" {
  grep -q "forge\.stage" "$OBSERVABILITY" \
    || fail "Missing forge attribute: forge.stage"
}

@test "observability: documents forge.findings.count attribute" {
  grep -q "forge\.findings\.count" "$OBSERVABILITY" \
    || fail "Missing forge attribute: forge.findings.count"
}

# ---------------------------------------------------------------------------
# 5. Cardinality-safe span name patterns
# ---------------------------------------------------------------------------
@test "observability: lists pipeline span-name pattern" {
  grep -q "pipeline" "$OBSERVABILITY" \
    || fail "Cardinality budget missing 'pipeline' span name"
}

@test "observability: lists stage span-name pattern" {
  grep -qE "stage\.<STAGE>|stage\." "$OBSERVABILITY" \
    || fail "Cardinality budget missing 'stage.<STAGE>' span name"
}

@test "observability: lists agent span-name pattern" {
  grep -qE "agent\.<agent_name>|agent\." "$OBSERVABILITY" \
    || fail "Cardinality budget missing 'agent.<agent_name>' span name"
}

@test "observability: lists tool span-name pattern" {
  grep -qE "tool\.<tool_name>|tool\." "$OBSERVABILITY" \
    || fail "Cardinality budget missing 'tool.<tool_name>' span name"
}

@test "observability: lists batch span-name pattern" {
  grep -q "batch\.review-round" "$OBSERVABILITY" \
    || fail "Cardinality budget missing 'batch.review-round-<N>' span name"
}

# ---------------------------------------------------------------------------
# 6. Exporter options
# ---------------------------------------------------------------------------
@test "observability: documents grpc exporter option" {
  grep -qE "\bgrpc\b" "$OBSERVABILITY" \
    || fail "grpc exporter not documented"
}

@test "observability: documents http exporter option" {
  grep -qE "\bhttp\b" "$OBSERVABILITY" \
    || fail "http exporter not documented"
}

@test "observability: documents console exporter option" {
  grep -qE "\bconsole\b" "$OBSERVABILITY" \
    || fail "console exporter not documented"
}

# ---------------------------------------------------------------------------
# 7. Replay / durability contract
# ---------------------------------------------------------------------------
@test "observability: documents otel.replay() as authoritative" {
  grep -q "replay" "$OBSERVABILITY" \
    || fail "otel.replay() not documented"
}

@test "observability: documents events.jsonl source of truth" {
  grep -q "events\.jsonl" "$OBSERVABILITY" \
    || fail "events.jsonl durability source not documented"
}

# ---------------------------------------------------------------------------
# 8. Attribute rename migration table
# ---------------------------------------------------------------------------
@test "observability: documents tokens_in → gen_ai.tokens.input rename" {
  grep -q "tokens_in" "$OBSERVABILITY" \
    || fail "Migration table missing tokens_in → gen_ai.tokens.input"
}

@test "observability: documents tokens_out → gen_ai.tokens.output rename" {
  grep -q "tokens_out" "$OBSERVABILITY" \
    || fail "Migration table missing tokens_out → gen_ai.tokens.output"
}
