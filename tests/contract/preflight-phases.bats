#!/usr/bin/env bats
# Contract tests: PREFLIGHT phase decomposition into Config/Integration/Workspace groups

load '../helpers/test-helpers'

BOOT_DOC="$PLUGIN_ROOT/agents/fg-100-orchestrator-boot.md"
STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"

# ---------------------------------------------------------------------------
# 1. Config Group and Integration Group documented
# ---------------------------------------------------------------------------
@test "preflight-phases: Config Group and Integration Group documented" {
  grep -q "Config Group" "$BOOT_DOC" \
    || fail "Config Group not documented in boot doc"
  grep -q "Integration Group" "$BOOT_DOC" \
    || fail "Integration Group not documented in boot doc"
}

# ---------------------------------------------------------------------------
# 2. Phase B (Workspace) documented
# ---------------------------------------------------------------------------
@test "preflight-phases: Phase B (Workspace) documented" {
  grep -q "Phase B" "$BOOT_DOC" \
    || fail "Phase B not documented in boot doc"
}

# ---------------------------------------------------------------------------
# 3. MCP mentioned in Integration Group
# ---------------------------------------------------------------------------
@test "preflight-phases: MCP mentioned in context of Integration Group" {
  grep -qi "MCP" "$BOOT_DOC" \
    || fail "MCP not mentioned in boot doc"
}

# ---------------------------------------------------------------------------
# 4. Worktree mentioned in Phase B
# ---------------------------------------------------------------------------
@test "preflight-phases: worktree mentioned in Phase B context" {
  # Phase B should reference worktree creation
  grep -q "worktree" "$BOOT_DOC" \
    || fail "worktree not mentioned in boot doc"
}

# ---------------------------------------------------------------------------
# 5. Degraded handling documented (integration failures)
# ---------------------------------------------------------------------------
@test "preflight-phases: degraded handling for integration failures documented" {
  grep -qi "degraded" "$BOOT_DOC" \
    || fail "Degraded handling not documented in boot doc"
}

# ---------------------------------------------------------------------------
# 6. Abort on config failure documented
# ---------------------------------------------------------------------------
@test "preflight-phases: abort on config failure documented" {
  grep -qi "abort.*config\|config.*abort\|config.*fail.*abort\|abort.*Config Group\|Config Group.*abort" "$BOOT_DOC" \
    || fail "Abort on config failure not documented in boot doc"
}

# ---------------------------------------------------------------------------
# 7. Phase B depends on Phase A (dependency documented)
# ---------------------------------------------------------------------------
@test "preflight-phases: Phase B dependency on Phase A documented" {
  grep -qiE "Phase B.*after.*Phase A|Phase A.*before.*Phase B|Phase B.*requires.*Phase A|Phase B.*depends|Phase A.*complet.*Phase B" "$BOOT_DOC" \
    || fail "Phase B dependency on Phase A not documented"
}

# ---------------------------------------------------------------------------
# 8. Stage contract references boot doc phase structure
# ---------------------------------------------------------------------------
@test "preflight-phases: stage contract references boot doc phase structure" {
  grep -qi "phase.*group\|Config Group\|Integration Group\|orchestrator-boot" "$STAGE_CONTRACT" \
    || fail "Stage contract does not reference boot doc phase structure"
}
