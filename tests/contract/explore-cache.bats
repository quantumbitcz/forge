#!/usr/bin/env bats
# Contract tests: explore-cache.md existence and required sections.

load '../helpers/test-helpers'

EXPLORE_CACHE="$PLUGIN_ROOT/shared/explore-cache.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "explore-cache: shared/explore-cache.md exists" {
  [ -f "$EXPLORE_CACHE" ] || fail "shared/explore-cache.md not found"
}

# ---------------------------------------------------------------------------
# 2. Required sections
# ---------------------------------------------------------------------------
@test "explore-cache: contains ## Cache Schema" {
  grep -q "^## Cache Schema" "$EXPLORE_CACHE" \
    || fail "Missing required section: ## Cache Schema"
}

@test "explore-cache: contains ## Invalidation Rules" {
  grep -q "^## Invalidation Rules" "$EXPLORE_CACHE" \
    || fail "Missing required section: ## Invalidation Rules"
}

@test "explore-cache: contains ## PREFLIGHT Integration" {
  grep -q "^## PREFLIGHT Integration" "$EXPLORE_CACHE" \
    || fail "Missing required section: ## PREFLIGHT Integration"
}

# ---------------------------------------------------------------------------
# 3. Schema fields documented
# ---------------------------------------------------------------------------
@test "explore-cache: documents schema_version field" {
  grep -q "schema_version" "$EXPLORE_CACHE" \
    || fail "schema_version field not documented"
}

@test "explore-cache: documents last_explored_sha field" {
  grep -q "last_explored_sha" "$EXPLORE_CACHE" \
    || fail "last_explored_sha field not documented"
}

@test "explore-cache: documents file_index field" {
  grep -q "file_index" "$EXPLORE_CACHE" \
    || fail "file_index field not documented"
}

# ---------------------------------------------------------------------------
# 4. Partial re-explore documented
# ---------------------------------------------------------------------------
@test "explore-cache: contains ## Partial Re-Explore" {
  grep -q "^## Partial Re-Explore" "$EXPLORE_CACHE" \
    || fail "Missing required section: ## Partial Re-Explore"
}

# ---------------------------------------------------------------------------
# 5. Configuration documented
# ---------------------------------------------------------------------------
@test "explore-cache: contains ## Configuration" {
  grep -q "^## Configuration" "$EXPLORE_CACHE" \
    || fail "Missing required section: ## Configuration"
}

@test "explore-cache: documents cache_enabled parameter" {
  grep -q "cache_enabled" "$EXPLORE_CACHE" \
    || fail "cache_enabled parameter not documented"
}

@test "explore-cache: documents max_cache_age_runs parameter" {
  grep -q "max_cache_age_runs" "$EXPLORE_CACHE" \
    || fail "max_cache_age_runs parameter not documented"
}

# ---------------------------------------------------------------------------
# 6. Reset behavior documented
# ---------------------------------------------------------------------------
@test "explore-cache: documents /forge-reset behavior" {
  grep -q "forge-reset" "$EXPLORE_CACHE" \
    || fail "/forge-reset behavior not documented"
}
