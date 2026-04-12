#!/usr/bin/env bats
# Contract tests: shared/forge-token-tracker.sh — structural validation of the token tracker.

load '../helpers/test-helpers'

TRACKER="$PLUGIN_ROOT/shared/forge-token-tracker.sh"

# ---------------------------------------------------------------------------
# 1. Script exists and is executable
# ---------------------------------------------------------------------------
@test "token-tracker: script exists and is executable" {
  [[ -f "$TRACKER" ]] || fail "forge-token-tracker.sh does not exist"
  [[ -x "$TRACKER" ]] || fail "forge-token-tracker.sh is not executable"
}

# ---------------------------------------------------------------------------
# 2. Script contains do_record function
# ---------------------------------------------------------------------------
@test "token-tracker: contains do_record function" {
  grep -qE '^do_record\(\)' "$TRACKER" \
    || fail "do_record() function not found in forge-token-tracker.sh"
}

# ---------------------------------------------------------------------------
# 3. Script accepts model parameter
# ---------------------------------------------------------------------------
@test "token-tracker: accepts model parameter" {
  grep -q 'MODEL' "$TRACKER" \
    || fail "MODEL variable not found — script should accept a model parameter"
}

# ---------------------------------------------------------------------------
# 4. Script contains PRICING dict
# ---------------------------------------------------------------------------
@test "token-tracker: contains PRICING dict" {
  grep -q 'PRICING' "$TRACKER" \
    || fail "PRICING dict not found in forge-token-tracker.sh"
}

# ---------------------------------------------------------------------------
# 5. PRICING includes haiku, sonnet, and opus tiers
# ---------------------------------------------------------------------------
@test "token-tracker: PRICING covers haiku, sonnet, and opus" {
  for model in haiku sonnet opus; do
    grep -q "\"$model\"" "$TRACKER" \
      || fail "PRICING does not include $model"
  done
}

# ---------------------------------------------------------------------------
# 6. Script contains model_distribution computation
# ---------------------------------------------------------------------------
@test "token-tracker: contains model_distribution computation" {
  grep -q 'model_distribution' "$TRACKER" \
    || fail "model_distribution computation not found in forge-token-tracker.sh"
}

# ---------------------------------------------------------------------------
# 7. Script contains estimated_cost_usd computation
# ---------------------------------------------------------------------------
@test "token-tracker: contains estimated_cost_usd computation" {
  grep -q 'estimated_cost_usd' "$TRACKER" \
    || fail "estimated_cost_usd computation not found in forge-token-tracker.sh"
}

# ---------------------------------------------------------------------------
# 8. No duplicated Python blocks — shared _TOKEN_UPDATE_PY variable exists
# ---------------------------------------------------------------------------
@test "token-tracker: uses shared _TOKEN_UPDATE_PY variable (no duplicated Python)" {
  grep -q '_TOKEN_UPDATE_PY' "$TRACKER" \
    || fail "_TOKEN_UPDATE_PY shared variable not found — Python block may be duplicated"
  # The variable should be defined exactly once (assignment) and referenced
  local def_count
  def_count=$(grep -c '_TOKEN_UPDATE_PY=' "$TRACKER")
  [[ "$def_count" -eq 1 ]] \
    || fail "Expected exactly 1 _TOKEN_UPDATE_PY assignment, found $def_count"
}

# ---------------------------------------------------------------------------
# 9. Script has proper shebang
# ---------------------------------------------------------------------------
@test "token-tracker: has bash shebang" {
  local first_line
  first_line="$(head -1 "$TRACKER")"
  [[ "$first_line" =~ ^#!.*bash ]] || fail "Missing bash shebang: $first_line"
}

# ---------------------------------------------------------------------------
# 10. Script references forge-state-write.sh for atomic writes
# ---------------------------------------------------------------------------
@test "token-tracker: references forge-state-write.sh" {
  grep -q 'forge-state-write.sh' "$TRACKER" \
    || fail "forge-token-tracker.sh does not reference forge-state-write.sh"
}
