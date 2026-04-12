#!/usr/bin/env bats
# Contract tests: model-routing.md existence and required sections.

load '../helpers/test-helpers'

MODEL_ROUTING="$PLUGIN_ROOT/shared/model-routing.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "model-routing: shared/model-routing.md exists" {
  [ -f "$MODEL_ROUTING" ] || fail "shared/model-routing.md not found"
}

# ---------------------------------------------------------------------------
# 2. Required sections
# ---------------------------------------------------------------------------
@test "model-routing: contains ## Tier Definitions" {
  grep -q "^## Tier Definitions" "$MODEL_ROUTING" \
    || fail "Missing required section: ## Tier Definitions"
}

@test "model-routing: contains ## Resolution Order" {
  grep -q "^## Resolution Order" "$MODEL_ROUTING" \
    || fail "Missing required section: ## Resolution Order"
}

@test "model-routing: contains ## PREFLIGHT Constraints" {
  grep -q "^## PREFLIGHT Constraints" "$MODEL_ROUTING" \
    || fail "Missing required section: ## PREFLIGHT Constraints"
}

# ---------------------------------------------------------------------------
# 3. Tier definitions cover all three tiers
# ---------------------------------------------------------------------------
@test "model-routing: defines fast tier" {
  grep -q '`fast`\|fast.*haiku' "$MODEL_ROUTING" \
    || fail "fast tier not defined in Tier Definitions"
}

@test "model-routing: defines standard tier" {
  grep -q '`standard`\|standard.*sonnet' "$MODEL_ROUTING" \
    || fail "standard tier not defined in Tier Definitions"
}

@test "model-routing: defines premium tier" {
  grep -q '`premium`\|premium.*opus' "$MODEL_ROUTING" \
    || fail "premium tier not defined in Tier Definitions"
}

# ---------------------------------------------------------------------------
# 4. Fallback behavior documented
# ---------------------------------------------------------------------------
@test "model-routing: documents fallback behavior" {
  grep -q "## Fallback Behavior\|fallback" "$MODEL_ROUTING" \
    || fail "Fallback behavior not documented"
}

# ---------------------------------------------------------------------------
# 5. PREFLIGHT constraints include enabled and default_tier
# ---------------------------------------------------------------------------
@test "model-routing: PREFLIGHT constraints include model_routing.enabled" {
  grep -q "model_routing.enabled\|model_routing\.enabled" "$MODEL_ROUTING" \
    || fail "model_routing.enabled not in PREFLIGHT constraints"
}

@test "model-routing: PREFLIGHT constraints include model_routing.default_tier" {
  grep -q "model_routing.default_tier\|model_routing\.default_tier" "$MODEL_ROUTING" \
    || fail "model_routing.default_tier not in PREFLIGHT constraints"
}
