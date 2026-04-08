#!/usr/bin/env bats
# Contract tests: shared/domain-detection.md — validates the domain detection document.

load '../helpers/test-helpers'

DOMAIN_DETECTION="$PLUGIN_ROOT/shared/domain-detection.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "domain-detection: document exists" {
  [[ -f "$DOMAIN_DETECTION" ]]
}

# ---------------------------------------------------------------------------
# 2. Algorithm section exists
# ---------------------------------------------------------------------------
@test "domain-detection: algorithm section exists" {
  grep -q "## Detection Algorithm" "$DOMAIN_DETECTION" \
    || fail "Detection Algorithm section not found"
  grep -q "### Step 1" "$DOMAIN_DETECTION" \
    || fail "Step 1 (Extract Signals) not found"
  grep -q "### Step 2" "$DOMAIN_DETECTION" \
    || fail "Step 2 (Vote) not found"
  grep -q "### Step 3" "$DOMAIN_DETECTION" \
    || fail "Step 3 (Validate) not found"
  grep -q "### Step 4" "$DOMAIN_DETECTION" \
    || fail "Step 4 (Log) not found"
}

# ---------------------------------------------------------------------------
# 3. Valid domain values listed
# ---------------------------------------------------------------------------
@test "domain-detection: known domains listed" {
  grep -q "## Known Domains" "$DOMAIN_DETECTION" \
    || fail "Known Domains section not found"
  for domain in auth billing user scheduling communication inventory workflow commerce search analytics config api infra general; do
    grep -q "\`${domain}\`" "$DOMAIN_DETECTION" \
      || fail "Known domain '${domain}' not listed"
  done
}

# ---------------------------------------------------------------------------
# 4. Fallback behavior documented (unknown/general)
# ---------------------------------------------------------------------------
@test "domain-detection: fallback to general documented" {
  grep -q "general" "$DOMAIN_DETECTION" \
    || fail "'general' fallback not mentioned"
  grep -iq "fallback" "$DOMAIN_DETECTION" \
    || fail "Fallback behavior not documented"
  grep -q "fall back to \`general\`\|fallback.*general\|defaults to.*general" "$DOMAIN_DETECTION" \
    || fail "Fallback to 'general' rule not documented"
}

# ---------------------------------------------------------------------------
# 5. Validation rules documented
# ---------------------------------------------------------------------------
@test "domain-detection: validation rules documented" {
  grep -q "## Validation Rules" "$DOMAIN_DETECTION" \
    || fail "Validation Rules section not found"
  grep -q "non-empty" "$DOMAIN_DETECTION" \
    || fail "Non-empty validation rule not documented"
  grep -q "lowercase" "$DOMAIN_DETECTION" \
    || fail "Lowercase validation rule not documented"
  grep -q "immutable" "$DOMAIN_DETECTION" \
    || fail "Immutability rule not documented"
}

# ---------------------------------------------------------------------------
# 6. Logging requirements documented
# ---------------------------------------------------------------------------
@test "domain-detection: logging requirements documented" {
  grep -q "### Step 4" "$DOMAIN_DETECTION" \
    || fail "Step 4 (Log) not found"
  grep -iq "signals" "$DOMAIN_DETECTION" \
    || fail "Signal logging not documented"
  grep -iq "confidence" "$DOMAIN_DETECTION" \
    || fail "Confidence logging not documented"
}

# ---------------------------------------------------------------------------
# 7. Orchestrator references domain-detection.md
# ---------------------------------------------------------------------------
@test "domain-detection: orchestrator references domain-detection.md" {
  grep -q "domain-detection.md" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference domain-detection.md"
}

# ---------------------------------------------------------------------------
# 8. State-schema references domain-detection.md
# ---------------------------------------------------------------------------
@test "domain-detection: state-schema references domain-detection.md" {
  grep -q "domain-detection.md" "$STATE_SCHEMA" \
    || fail "State-schema does not reference domain-detection.md"
}
