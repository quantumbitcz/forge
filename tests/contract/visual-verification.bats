#!/usr/bin/env bats
# Contract tests: visual-verification.md existence and required sections.

load '../helpers/test-helpers'

VISUAL_VERIFICATION="$PLUGIN_ROOT/shared/visual-verification.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "visual-verification: shared/visual-verification.md exists" {
  [ -f "$VISUAL_VERIFICATION" ] || fail "shared/visual-verification.md not found"
}

# ---------------------------------------------------------------------------
# 2. Required sections
# ---------------------------------------------------------------------------
@test "visual-verification: contains ## Screenshot Strategy" {
  grep -q "^## Screenshot Strategy" "$VISUAL_VERIFICATION" \
    || fail "Missing required section: ## Screenshot Strategy"
}

@test "visual-verification: contains ## Breakpoints" {
  grep -q "^### Breakpoints" "$VISUAL_VERIFICATION" \
    || fail "Missing required section: ### Breakpoints"
}

@test "visual-verification: contains ## Graceful Degradation" {
  grep -q "^## Graceful Degradation" "$VISUAL_VERIFICATION" \
    || fail "Missing required section: ## Graceful Degradation"
}

@test "visual-verification: contains ## Configuration" {
  grep -q "^## Configuration" "$VISUAL_VERIFICATION" \
    || fail "Missing required section: ## Configuration"
}

@test "visual-verification: contains ## Prerequisites" {
  grep -q "^## Prerequisites" "$VISUAL_VERIFICATION" \
    || fail "Missing required section: ## Prerequisites"
}

@test "visual-verification: contains ## Finding Categories" {
  grep -q "^## Finding Categories" "$VISUAL_VERIFICATION" \
    || fail "Missing required section: ## Finding Categories"
}

# ---------------------------------------------------------------------------
# 3. Breakpoint values documented
# ---------------------------------------------------------------------------
@test "visual-verification: documents 375px breakpoint" {
  grep -q "375" "$VISUAL_VERIFICATION" \
    || fail "375px (mobile) breakpoint not documented"
}

@test "visual-verification: documents 768px breakpoint" {
  grep -q "768" "$VISUAL_VERIFICATION" \
    || fail "768px (tablet) breakpoint not documented"
}

@test "visual-verification: documents 1440px breakpoint" {
  grep -q "1440" "$VISUAL_VERIFICATION" \
    || fail "1440px (desktop) breakpoint not documented"
}

# ---------------------------------------------------------------------------
# 4. Finding categories documented
# ---------------------------------------------------------------------------
@test "visual-verification: documents FE-VISUAL-REGRESSION category" {
  grep -q "FE-VISUAL-REGRESSION" "$VISUAL_VERIFICATION" \
    || fail "FE-VISUAL-REGRESSION category not documented"
}

@test "visual-verification: documents FE-VISUAL-RESPONSIVE category" {
  grep -q "FE-VISUAL-RESPONSIVE" "$VISUAL_VERIFICATION" \
    || fail "FE-VISUAL-RESPONSIVE category not documented"
}

@test "visual-verification: documents FE-VISUAL-CONTRAST category" {
  grep -q "FE-VISUAL-CONTRAST" "$VISUAL_VERIFICATION" \
    || fail "FE-VISUAL-CONTRAST category not documented"
}

@test "visual-verification: documents FE-VISUAL-FIDELITY category" {
  grep -q "FE-VISUAL-FIDELITY" "$VISUAL_VERIFICATION" \
    || fail "FE-VISUAL-FIDELITY category not documented"
}

# ---------------------------------------------------------------------------
# 5. Graceful degradation covers key scenarios
# ---------------------------------------------------------------------------
@test "visual-verification: documents Playwright unavailable degradation" {
  grep -q "Playwright.*unavailable\|Playwright MCP unavailable" "$VISUAL_VERIFICATION" \
    || fail "Playwright unavailable degradation not documented"
}

@test "visual-verification: documents dev server degradation" {
  grep -q "Dev server\|dev_server_url" "$VISUAL_VERIFICATION" \
    || fail "Dev server degradation not documented"
}

# ---------------------------------------------------------------------------
# 6. Configuration parameters documented
# ---------------------------------------------------------------------------
@test "visual-verification: documents enabled parameter" {
  grep -q "enabled" "$VISUAL_VERIFICATION" \
    || fail "enabled parameter not documented"
}

@test "visual-verification: documents dev_server_url parameter" {
  grep -q "dev_server_url" "$VISUAL_VERIFICATION" \
    || fail "dev_server_url parameter not documented"
}

@test "visual-verification: documents breakpoints parameter" {
  grep -q "breakpoints" "$VISUAL_VERIFICATION" \
    || fail "breakpoints parameter not documented"
}

@test "visual-verification: documents pages parameter" {
  grep -q "pages" "$VISUAL_VERIFICATION" \
    || fail "pages parameter not documented"
}
