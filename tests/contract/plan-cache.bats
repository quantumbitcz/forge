#!/usr/bin/env bats
# Contract tests: plan-cache.md existence and required sections.

load '../helpers/test-helpers'

PLAN_CACHE="$PLUGIN_ROOT/shared/plan-cache.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "plan-cache: shared/plan-cache.md exists" {
  [ -f "$PLAN_CACHE" ] || fail "shared/plan-cache.md not found"
}

# ---------------------------------------------------------------------------
# 2. Required sections
# ---------------------------------------------------------------------------
@test "plan-cache: contains ## Cache Entry Schema" {
  grep -q "^## Cache Entry Schema" "$PLAN_CACHE" \
    || fail "Missing required section: ## Cache Entry Schema"
}

@test "plan-cache: contains ## Similarity Algorithm" {
  grep -q "^## Similarity Algorithm" "$PLAN_CACHE" \
    || fail "Missing required section: ## Similarity Algorithm"
}

@test "plan-cache: contains ## Eviction Rules" {
  grep -q "^## Eviction Rules" "$PLAN_CACHE" \
    || fail "Missing required section: ## Eviction Rules"
}

# ---------------------------------------------------------------------------
# 3. Schema fields documented
# ---------------------------------------------------------------------------
@test "plan-cache: documents schema_version field" {
  grep -q "schema_version" "$PLAN_CACHE" \
    || fail "schema_version field not documented"
}

@test "plan-cache: documents requirement field" {
  grep -q "requirement" "$PLAN_CACHE" \
    || fail "requirement field not documented"
}

@test "plan-cache: documents requirement_keywords field" {
  grep -q "requirement_keywords" "$PLAN_CACHE" \
    || fail "requirement_keywords field not documented"
}

@test "plan-cache: documents plan_hash field" {
  grep -q "plan_hash" "$PLAN_CACHE" \
    || fail "plan_hash field not documented"
}

@test "plan-cache: documents final_score field" {
  grep -q "final_score" "$PLAN_CACHE" \
    || fail "final_score field not documented"
}

# ---------------------------------------------------------------------------
# 4. Index schema documented
# ---------------------------------------------------------------------------
@test "plan-cache: contains ## Index Schema" {
  grep -q "^## Index Schema" "$PLAN_CACHE" \
    || fail "Missing required section: ## Index Schema"
}

# ---------------------------------------------------------------------------
# 5. Orchestrator integration documented
# ---------------------------------------------------------------------------
@test "plan-cache: contains ## Orchestrator Integration" {
  grep -q "^## Orchestrator Integration" "$PLAN_CACHE" \
    || fail "Missing required section: ## Orchestrator Integration"
}

# ---------------------------------------------------------------------------
# 6. Configuration documented
# ---------------------------------------------------------------------------
@test "plan-cache: contains ## Configuration" {
  grep -q "^## Configuration" "$PLAN_CACHE" \
    || fail "Missing required section: ## Configuration"
}

@test "plan-cache: documents similarity_threshold parameter" {
  grep -q "similarity_threshold" "$PLAN_CACHE" \
    || fail "similarity_threshold parameter not documented"
}

@test "plan-cache: documents max_entries parameter" {
  grep -q "max_entries" "$PLAN_CACHE" \
    || fail "max_entries parameter not documented"
}

# ---------------------------------------------------------------------------
# 7. Reset behavior documented
# ---------------------------------------------------------------------------
@test "plan-cache: documents /forge-reset behavior" {
  grep -q "forge-reset" "$PLAN_CACHE" \
    || fail "/forge-reset behavior not documented"
}
