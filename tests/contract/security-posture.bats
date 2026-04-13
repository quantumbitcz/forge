#!/usr/bin/env bats
# Contract tests: shared/security-posture.md — validates OWASP agentic security compliance.

load '../helpers/test-helpers'

SECURITY_POSTURE="$PLUGIN_ROOT/shared/security-posture.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "security-posture: document exists" {
  [[ -f "$SECURITY_POSTURE" ]]
}

# ---------------------------------------------------------------------------
# 2. Required sections present
# ---------------------------------------------------------------------------
@test "security-posture: OWASP Mapping section exists" {
  grep -q "## OWASP Top 10" "$SECURITY_POSTURE"
}

@test "security-posture: Tool Call Budget section exists" {
  grep -q "## Tool Call Budget" "$SECURITY_POSTURE"
}

@test "security-posture: Anomaly Detection section exists" {
  grep -q "## Anomaly Detection" "$SECURITY_POSTURE"
}

@test "security-posture: Input Sanitization section exists" {
  grep -q "## Input Sanitization" "$SECURITY_POSTURE"
}

@test "security-posture: Convention File Signatures section exists" {
  grep -q "## Convention File Signatures" "$SECURITY_POSTURE"
}

# ---------------------------------------------------------------------------
# 3. All 10 OWASP ASI risks documented
# ---------------------------------------------------------------------------
@test "security-posture: all 10 ASI risks mentioned (ASI01 through ASI10)" {
  for i in $(seq -w 1 10); do
    grep -q "ASI${i}" "$SECURITY_POSTURE" \
      || fail "ASI${i} not found in security-posture.md"
  done
}

# ---------------------------------------------------------------------------
# 4. OWASP table has required columns
# ---------------------------------------------------------------------------
@test "security-posture: OWASP table contains Risk Name, Current Mitigation, Enhancement columns" {
  grep -q "Risk Name" "$SECURITY_POSTURE" \
    || fail "Risk Name column not found"
  grep -q "Current Mitigation" "$SECURITY_POSTURE" \
    || fail "Current Mitigation column not found"
  grep -q "Enhancement" "$SECURITY_POSTURE" \
    || fail "Enhancement column not found"
}

# ---------------------------------------------------------------------------
# 5. Tool call budget defaults documented
# ---------------------------------------------------------------------------
@test "security-posture: tool call budget default is 50" {
  grep -q "default.*50\|50.*default" "$SECURITY_POSTURE" \
    || fail "Default tool call budget of 50 not found"
}

@test "security-posture: fg-300-implementer override documented as 200" {
  grep -q "fg-300-implementer.*200\|implementer.*200" "$SECURITY_POSTURE" \
    || fail "fg-300-implementer override of 200 not found"
}

@test "security-posture: fg-500-test-gate override documented as 150" {
  grep -q "fg-500-test-gate.*150\|test-gate.*150" "$SECURITY_POSTURE" \
    || fail "fg-500-test-gate override of 150 not found"
}

# ---------------------------------------------------------------------------
# 6. Anomaly detection thresholds documented
# ---------------------------------------------------------------------------
@test "security-posture: max_calls_per_minute threshold is 30" {
  grep -q "max_calls_per_minute.*30\|30.*calls.*minute" "$SECURITY_POSTURE" \
    || fail "max_calls_per_minute threshold of 30 not found"
}

@test "security-posture: max_session_cost_usd threshold is 10" {
  grep -q "max_session_cost_usd.*10\|\$10" "$SECURITY_POSTURE" \
    || fail "max_session_cost_usd threshold of 10 not found"
}

# ---------------------------------------------------------------------------
# 7. Input sanitization rules documented
# ---------------------------------------------------------------------------
@test "security-posture: input sanitization covers HTML tags" {
  grep -iq "HTML\|html.*tag\|<tag>" "$SECURITY_POSTURE" \
    || fail "HTML tag sanitization not documented"
}

@test "security-posture: input sanitization covers script tags" {
  grep -iq "script" "$SECURITY_POSTURE" \
    || fail "Script tag sanitization not documented"
}

@test "security-posture: input sanitization covers markdown injection" {
  grep -iq "markdown injection\|prompt injection" "$SECURITY_POSTURE" \
    || fail "Markdown/prompt injection sanitization not documented"
}

# ---------------------------------------------------------------------------
# 8. Convention file signatures use SHA256
# ---------------------------------------------------------------------------
@test "security-posture: convention signatures use SHA256" {
  grep -q "SHA256" "$SECURITY_POSTURE" \
    || fail "SHA256 not mentioned for convention file signatures"
}

# ---------------------------------------------------------------------------
# 9. Per-agent permission model documented
# ---------------------------------------------------------------------------
@test "security-posture: per-agent permission model documents all 4 tiers" {
  grep -q "Tier 1" "$SECURITY_POSTURE" || fail "Tier 1 not documented"
  grep -q "Tier 2" "$SECURITY_POSTURE" || fail "Tier 2 not documented"
  grep -q "Tier 3" "$SECURITY_POSTURE" || fail "Tier 3 not documented"
  grep -q "Tier 4" "$SECURITY_POSTURE" || fail "Tier 4 not documented"
}

# ---------------------------------------------------------------------------
# 10. Configuration YAML section exists with required keys
# ---------------------------------------------------------------------------
@test "security-posture: configuration documents security.input_sanitization" {
  grep -q "input_sanitization" "$SECURITY_POSTURE" \
    || fail "security.input_sanitization config not documented"
}

@test "security-posture: configuration documents security.tool_call_budget" {
  grep -q "tool_call_budget" "$SECURITY_POSTURE" \
    || fail "security.tool_call_budget config not documented"
}

@test "security-posture: configuration documents security.anomaly_detection" {
  grep -q "anomaly_detection" "$SECURITY_POSTURE" \
    || fail "security.anomaly_detection config not documented"
}

@test "security-posture: configuration documents security.convention_signatures" {
  grep -q "convention_signatures" "$SECURITY_POSTURE" \
    || fail "security.convention_signatures config not documented"
}

# ---------------------------------------------------------------------------
# 11. Sandbox documentation present
# ---------------------------------------------------------------------------
@test "security-posture: gVisor sandbox documented" {
  grep -q "gVisor" "$SECURITY_POSTURE" \
    || fail "gVisor sandbox option not documented"
}

@test "security-posture: Firecracker sandbox documented" {
  grep -q "Firecracker" "$SECURITY_POSTURE" \
    || fail "Firecracker sandbox option not documented"
}
