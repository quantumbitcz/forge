#!/usr/bin/env bats
# Contract tests: shared/agent-defaults.md — validates the shared agent defaults document.

load '../helpers/test-helpers'

AGENT_DEFAULTS="$PLUGIN_ROOT/shared/agent-defaults.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "agent-defaults: document exists" {
  [[ -f "$AGENT_DEFAULTS" ]]
}

# ---------------------------------------------------------------------------
# 2. Forbidden Actions section exists
# ---------------------------------------------------------------------------
@test "agent-defaults: Forbidden Actions section exists" {
  grep -q "Forbidden Actions" "$AGENT_DEFAULTS" \
    || fail "Forbidden Actions section not found"
}

# ---------------------------------------------------------------------------
# 3. Key forbidden actions documented
# ---------------------------------------------------------------------------
@test "agent-defaults: key forbidden actions documented (read-only, no contracts, no invent)" {
  grep -qi "DO NOT modify source files" "$AGENT_DEFAULTS" \
    || fail "Read-only source files rule not documented"
  grep -qi "DO NOT modify shared contracts" "$AGENT_DEFAULTS" \
    || fail "No shared contracts modification rule not documented"
  grep -qi "DO NOT invent findings" "$AGENT_DEFAULTS" \
    || fail "No inventing findings rule not documented"
}

# ---------------------------------------------------------------------------
# 4. Linear Tracking section exists
# ---------------------------------------------------------------------------
@test "agent-defaults: Linear Tracking section exists" {
  grep -q "Linear Tracking" "$AGENT_DEFAULTS" \
    || fail "Linear Tracking section not found"
}

# ---------------------------------------------------------------------------
# 5. Optional Integrations section exists
# ---------------------------------------------------------------------------
@test "agent-defaults: Optional Integrations section exists" {
  grep -q "Optional Integrations" "$AGENT_DEFAULTS" \
    || fail "Optional Integrations section not found"
  grep -qi "Context7 MCP" "$AGENT_DEFAULTS" \
    || fail "Context7 MCP not mentioned in Optional Integrations"
}

# ---------------------------------------------------------------------------
# 6. Standard Finding Format references output-format.md
# ---------------------------------------------------------------------------
@test "agent-defaults: Standard Finding Format references output-format.md" {
  grep -q "output-format.md" "$AGENT_DEFAULTS" \
    || fail "output-format.md not referenced in finding format section"
}

# ---------------------------------------------------------------------------
# 7. All 10 review agents listed
# ---------------------------------------------------------------------------
@test "agent-defaults: all 10 review agents listed" {
  local reviewers=(
    architecture-reviewer
    security-reviewer
    code-quality-reviewer
    frontend-reviewer
    frontend-a11y-reviewer
    frontend-performance-reviewer
    backend-performance-reviewer
    docs-consistency-reviewer
    infra-deploy-reviewer
    version-compat-reviewer
  )
  for reviewer in "${reviewers[@]}"; do
    grep -q "$reviewer" "$AGENT_DEFAULTS" \
      || fail "Review agent $reviewer not listed in agent-defaults.md"
  done
}

# ---------------------------------------------------------------------------
# 8. Convention stack layer resolution order documented
# ---------------------------------------------------------------------------
@test "agent-defaults: convention stack layer resolution order documented" {
  grep -qi "variant.*framework-binding.*framework.*language" "$AGENT_DEFAULTS" \
    || fail "Convention stack layer resolution order not documented"
}

# ---------------------------------------------------------------------------
# 9. Output budget documented
# ---------------------------------------------------------------------------
@test "agent-defaults: output budget documented (2000 tokens)" {
  grep -q "2,000 tokens" "$AGENT_DEFAULTS" \
    || fail "2,000 token output budget not documented"
}
