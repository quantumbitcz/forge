#!/usr/bin/env bats
# Contract tests: lsp-integration.md existence and required sections.

load '../helpers/test-helpers'

LSP_INTEGRATION="$PLUGIN_ROOT/shared/lsp-integration.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "lsp-integration: shared/lsp-integration.md exists" {
  [ -f "$LSP_INTEGRATION" ] || fail "shared/lsp-integration.md not found"
}

# ---------------------------------------------------------------------------
# 2. Required sections
# ---------------------------------------------------------------------------
@test "lsp-integration: contains ## When to Use LSP" {
  grep -q "^## When to Use LSP" "$LSP_INTEGRATION" \
    || fail "Missing required section: ## When to Use LSP"
}

@test "lsp-integration: contains ## Graceful Degradation" {
  grep -q "^## Graceful Degradation" "$LSP_INTEGRATION" \
    || fail "Missing required section: ## Graceful Degradation"
}

@test "lsp-integration: contains ## Supported Languages" {
  grep -q "^## Supported Languages" "$LSP_INTEGRATION" \
    || fail "Missing required section: ## Supported Languages"
}

@test "lsp-integration: contains ## Configuration" {
  grep -q "^## Configuration" "$LSP_INTEGRATION" \
    || fail "Missing required section: ## Configuration"
}

@test "lsp-integration: contains ## Agent Integration Pattern" {
  grep -q "^## Agent Integration Pattern" "$LSP_INTEGRATION" \
    || fail "Missing required section: ## Agent Integration Pattern"
}

# ---------------------------------------------------------------------------
# 3. Key agents documented
# ---------------------------------------------------------------------------
@test "lsp-integration: documents fg-412 architecture reviewer" {
  grep -q "fg-412" "$LSP_INTEGRATION" \
    || fail "fg-412 (architecture reviewer) not documented"
}

@test "lsp-integration: documents fg-300 implementer" {
  grep -q "fg-300" "$LSP_INTEGRATION" \
    || fail "fg-300 (implementer) not documented"
}

@test "lsp-integration: documents fg-416 performance reviewer" {
  grep -q "fg-416" "$LSP_INTEGRATION" \
    || fail "fg-416 (backend performance reviewer) not documented"
}

@test "lsp-integration: documents fg-410 code reviewer" {
  grep -q "fg-410" "$LSP_INTEGRATION" \
    || fail "fg-410 (code reviewer) not documented"
}

# ---------------------------------------------------------------------------
# 4. Graceful degradation is mandatory
# ---------------------------------------------------------------------------
@test "lsp-integration: degradation states LSP is optional" {
  grep -qi "optional\|fallback\|not required" "$LSP_INTEGRATION" \
    || fail "Graceful degradation does not state LSP is optional"
}

# ---------------------------------------------------------------------------
# 5. Configuration includes lsp.enabled
# ---------------------------------------------------------------------------
@test "lsp-integration: configuration includes lsp.enabled" {
  grep -q "lsp.enabled\|lsp\.enabled" "$LSP_INTEGRATION" \
    || fail "lsp.enabled not documented in Configuration"
}

@test "lsp-integration: configuration includes lsp.languages" {
  grep -q "lsp.languages\|lsp\.languages" "$LSP_INTEGRATION" \
    || fail "lsp.languages not documented in Configuration"
}
