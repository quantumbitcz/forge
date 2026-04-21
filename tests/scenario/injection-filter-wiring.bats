#!/usr/bin/env bats
# Orchestrator + key consumer agents reference the injection filter.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "orchestrator doc references mcp_response_filter.py" {
  grep -q "hooks/_py/mcp_response_filter.py" "$ROOT/agents/fg-100-orchestrator.md"
}

@test "orchestrator doc describes the T-C + Bash confirmation gate" {
  grep -qE "Confirmed.*Bash|T-C.*Bash" "$ROOT/agents/fg-100-orchestrator.md"
}

@test "bug-investigator references filter for ticket-body ingress" {
  grep -q "mcp_response_filter" "$ROOT/agents/fg-020-bug-investigator.md"
}

@test "orchestrator doc references untrusted-envelope contract" {
  grep -q "shared/untrusted-envelope.md" "$ROOT/agents/fg-100-orchestrator.md"
}

@test "orchestrator doc mentions INJECTION_BLOCKED handling" {
  grep -q "INJECTION_BLOCKED" "$ROOT/agents/fg-100-orchestrator.md"
}
