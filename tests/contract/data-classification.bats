#!/usr/bin/env bats
# Contract tests: data-classification.md existence and required sections.

load '../helpers/test-helpers'

DATA_CLASS="$PLUGIN_ROOT/shared/data-classification.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "data-classification: shared/data-classification.md exists" {
  [ -f "$DATA_CLASS" ] || fail "shared/data-classification.md not found"
}

# ---------------------------------------------------------------------------
# 2. Required sections
# ---------------------------------------------------------------------------
@test "data-classification: contains ## Classification Tiers" {
  grep -q "^## Classification Tiers" "$DATA_CLASS" \
    || fail "Missing required section: ## Classification Tiers"
}

@test "data-classification: contains ## Detection Patterns" {
  grep -q "^## Detection Patterns" "$DATA_CLASS" \
    || fail "Missing required section: ## Detection Patterns"
}

@test "data-classification: contains ## Redaction Rules" {
  grep -q "^## Redaction Rules" "$DATA_CLASS" \
    || fail "Missing required section: ## Redaction Rules"
}

@test "data-classification: contains ## Configuration" {
  grep -q "^## Configuration" "$DATA_CLASS" \
    || fail "Missing required section: ## Configuration"
}

# ---------------------------------------------------------------------------
# 3. Tier names present
# ---------------------------------------------------------------------------
@test "data-classification: documents PUBLIC tier" {
  grep -q "PUBLIC" "$DATA_CLASS" \
    || fail "PUBLIC tier not documented"
}

@test "data-classification: documents INTERNAL tier" {
  grep -q "INTERNAL" "$DATA_CLASS" \
    || fail "INTERNAL tier not documented"
}

@test "data-classification: documents CONFIDENTIAL tier" {
  grep -q "CONFIDENTIAL" "$DATA_CLASS" \
    || fail "CONFIDENTIAL tier not documented"
}

@test "data-classification: documents RESTRICTED tier" {
  grep -q "RESTRICTED" "$DATA_CLASS" \
    || fail "RESTRICTED tier not documented"
}

# ---------------------------------------------------------------------------
# 4. Category codes present
# ---------------------------------------------------------------------------
@test "data-classification: documents SEC-SECRET category" {
  grep -q "SEC-SECRET" "$DATA_CLASS" \
    || fail "SEC-SECRET category not documented"
}

@test "data-classification: documents SEC-PII category" {
  grep -q "SEC-PII" "$DATA_CLASS" \
    || fail "SEC-PII category not documented"
}

@test "data-classification: documents SEC-REDACT category" {
  grep -q "SEC-REDACT" "$DATA_CLASS" \
    || fail "SEC-REDACT category not documented"
}

# ---------------------------------------------------------------------------
# 5. Detection patterns documented
# ---------------------------------------------------------------------------
@test "data-classification: documents API key/token detection regex" {
  grep -q "api.*key\|token\|password" "$DATA_CLASS" \
    || fail "API key/token detection pattern not documented"
}

@test "data-classification: documents private key detection regex" {
  grep -q "PRIVATE KEY" "$DATA_CLASS" \
    || fail "Private key detection pattern not documented"
}

# ---------------------------------------------------------------------------
# 6. Configuration parameters documented
# ---------------------------------------------------------------------------
@test "data-classification: documents enabled parameter" {
  grep -q "enabled" "$DATA_CLASS" \
    || fail "enabled parameter not documented"
}

@test "data-classification: documents redact_artifacts parameter" {
  grep -q "redact_artifacts" "$DATA_CLASS" \
    || fail "redact_artifacts parameter not documented"
}

@test "data-classification: documents custom_patterns parameter" {
  grep -q "custom_patterns" "$DATA_CLASS" \
    || fail "custom_patterns parameter not documented"
}

@test "data-classification: documents pii_detection parameter" {
  grep -q "pii_detection" "$DATA_CLASS" \
    || fail "pii_detection parameter not documented"
}

@test "data-classification: documents block_restricted parameter" {
  grep -q "block_restricted" "$DATA_CLASS" \
    || fail "block_restricted parameter not documented"
}

# ---------------------------------------------------------------------------
# 7. Check engine integration documented
# ---------------------------------------------------------------------------
@test "data-classification: contains ## Check Engine Integration" {
  grep -q "^## Check Engine Integration" "$DATA_CLASS" \
    || fail "Missing required section: ## Check Engine Integration"
}

# ---------------------------------------------------------------------------
# 8. Finding categories section documented
# ---------------------------------------------------------------------------
@test "data-classification: contains ## Finding Categories" {
  grep -q "^## Finding Categories" "$DATA_CLASS" \
    || fail "Missing required section: ## Finding Categories"
}
