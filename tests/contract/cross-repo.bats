#!/usr/bin/env bats
# Contract tests: cross-repo features — validates cross-repo documentation and state fields.

load '../helpers/test-helpers'

STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
STATE_SCHEMA_FIELDS="$PLUGIN_ROOT/shared/state-schema-fields.md"
STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
FORGE_INIT="$PLUGIN_ROOT/skills/forge/SKILL.md"

# ---------------------------------------------------------------------------
# 1. cross_repo field documented in state-schema.md
# ---------------------------------------------------------------------------
@test "cross-repo: cross_repo field documented in state-schema" {
  grep -q "cross_repo" "$STATE_SCHEMA" \
    || fail "cross_repo field not documented in state-schema.md"
}

# ---------------------------------------------------------------------------
# 2. cross_repo sub-fields documented (path, branch, status, files_changed, pr_url)
# ---------------------------------------------------------------------------
@test "cross-repo: cross_repo sub-fields documented" {
  local combined
  combined="$(cat "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" "$CLAUDE_MD")"
  for field in path branch status files_changed pr_url; do
    printf '%s' "$combined" | grep -q "$field" \
      || fail "cross_repo sub-field '$field' not documented"
  done
}

# ---------------------------------------------------------------------------
# 3. 5-step discovery documented
# ---------------------------------------------------------------------------
@test "cross-repo: 5-step discovery process documented" {
  grep -qi "5.*step.*discover\|discovery" "$CLAUDE_MD" \
    || fail "5-step cross-repo discovery not documented in CLAUDE.md"
}

# ---------------------------------------------------------------------------
# 4. Pipeline-init handles cross-repo discovery
# ---------------------------------------------------------------------------
@test "cross-repo: forge-init skill includes cross-repo discovery phase" {
  grep -qi "cross.repo\|CROSS-REPO\|related.*project\|related_projects" "$FORGE_INIT" \
    || fail "Cross-repo discovery not mentioned in forge-init skill"
}

# ---------------------------------------------------------------------------
# 5. Cross-repo timeout documented
# ---------------------------------------------------------------------------
@test "cross-repo: timeout documented in CLAUDE.md" {
  grep -qi "cross.repo.*timeout\|timeout.*30.*minutes\|timeout_minutes" "$CLAUDE_MD" \
    || fail "Cross-repo timeout not documented"
}

# ---------------------------------------------------------------------------
# 6. Cross-repo PR failure isolation documented
# ---------------------------------------------------------------------------
@test "cross-repo: PR failures dont block main PR documented" {
  grep -qi "PR failures don.t block\|don.t block main PR\|cross.repo.*fail.*unaffect\|main PR unaffected" "$CLAUDE_MD" \
    || fail "Cross-repo PR failure isolation not documented"
}

# ---------------------------------------------------------------------------
# 7. Lock ordering documented for deadlock prevention
# ---------------------------------------------------------------------------
@test "cross-repo: alphabetical lock ordering documented" {
  grep -qi "alphabetical.*lock\|lock.*ordering\|lock.*alphabetical" "$CLAUDE_MD" \
    || fail "Alphabetical lock ordering for deadlock prevention not documented"
}

# ---------------------------------------------------------------------------
# 8. detected_via field documented for discovery results
# ---------------------------------------------------------------------------
@test "cross-repo: detected_via field documented" {
  grep -q "detected_via" "$CLAUDE_MD" \
    || fail "detected_via field not documented in CLAUDE.md"
}

# ---------------------------------------------------------------------------
# 9. Contract validator agent exists for cross-repo validation
# ---------------------------------------------------------------------------
@test "cross-repo: fg-250-contract-validator agent exists" {
  [[ -f "$PLUGIN_ROOT/agents/fg-250-contract-validator.md" ]] \
    || fail "fg-250-contract-validator agent not found"
}
