#!/usr/bin/env bats
# Contract tests: event-driven automations

load '../helpers/test-helpers'

AUTOMATIONS="$PLUGIN_ROOT/shared/automations.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "automations-contract: shared/automations.md exists" {
  [[ -f "$AUTOMATIONS" ]] \
    || fail "shared/automations.md does not exist"
}

# ---------------------------------------------------------------------------
# 2. Required section: Trigger Types
# ---------------------------------------------------------------------------
@test "automations-contract: has Trigger Types section" {
  grep -q "## Trigger Types" "$AUTOMATIONS" \
    || fail "Missing '## Trigger Types' section"
}

# ---------------------------------------------------------------------------
# 3. Required section: Safety Constraints
# ---------------------------------------------------------------------------
@test "automations-contract: has Safety Constraints section" {
  grep -q "## Safety Constraints" "$AUTOMATIONS" \
    || fail "Missing '## Safety Constraints' section"
}

# ---------------------------------------------------------------------------
# 4. Required section: Configuration
# ---------------------------------------------------------------------------
@test "automations-contract: has Configuration section" {
  grep -q "## Configuration" "$AUTOMATIONS" \
    || fail "Missing '## Configuration' section"
}

# ---------------------------------------------------------------------------
# 5. Required section: Cooldown Rules
# ---------------------------------------------------------------------------
@test "automations-contract: has Cooldown Rules section" {
  grep -q "## Cooldown Rules" "$AUTOMATIONS" \
    || fail "Missing '## Cooldown Rules' section"
}

# ---------------------------------------------------------------------------
# 6. All trigger types documented
# ---------------------------------------------------------------------------
@test "automations-contract: all 6 trigger types documented" {
  for trigger in cron ci_failure pr_opened dependabot_pr linear_status file_changed; do
    grep -q "$trigger" "$AUTOMATIONS" \
      || fail "Trigger type '$trigger' not found in automations.md"
  done
}

# ---------------------------------------------------------------------------
# 7. Schema defines required fields
# ---------------------------------------------------------------------------
@test "automations-contract: schema defines required fields (name, trigger, action, filter, cooldown_minutes)" {
  for field in name trigger action filter cooldown_minutes; do
    grep -q "$field" "$AUTOMATIONS" \
      || fail "Required field '$field' not found in automations.md"
  done
}

# ---------------------------------------------------------------------------
# 8. Log file location documented
# ---------------------------------------------------------------------------
@test "automations-contract: log location is .forge/automation-log.jsonl" {
  grep -q "\.forge/automation-log\.jsonl" "$AUTOMATIONS" \
    || fail ".forge/automation-log.jsonl location not documented"
}

# ---------------------------------------------------------------------------
# 9. Max concurrent limit documented
# ---------------------------------------------------------------------------
@test "automations-contract: max 3 concurrent automations documented" {
  grep -q "3 concurrent" "$AUTOMATIONS" \
    || fail "Max concurrent automation limit not documented"
}

# ---------------------------------------------------------------------------
# 10. Destructive actions require approval
# ---------------------------------------------------------------------------
@test "automations-contract: destructive actions require human approval" {
  grep -q "human approval\|user confirmation" "$AUTOMATIONS" \
    || fail "Destructive action approval requirement not documented"
}
