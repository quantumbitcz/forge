#!/usr/bin/env bats
# Contract tests: circuit breaker pattern in recovery engine

load '../helpers/test-helpers'

RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# 1. Circuit Breaker section exists in recovery engine
# ---------------------------------------------------------------------------
@test "circuit-breaker-contract: section 8.1 Circuit Breaker exists in recovery-engine.md" {
  grep -q "## 8.1 Circuit Breaker" "$RECOVERY_ENGINE" \
    || fail "Section 8.1 Circuit Breaker not found in recovery-engine.md"
}

# ---------------------------------------------------------------------------
# 2. Three states documented (closed, open, half-open)
# ---------------------------------------------------------------------------
@test "circuit-breaker-contract: three states documented (CLOSED, OPEN, HALF_OPEN)" {
  grep -qi "CLOSED" "$RECOVERY_ENGINE" \
    || fail "CLOSED state not documented"
  grep -qi "OPEN" "$RECOVERY_ENGINE" \
    || fail "OPEN state not documented"
  grep -qi "HALF_OPEN\|HALF-OPEN\|half.open" "$RECOVERY_ENGINE" \
    || fail "HALF_OPEN state not documented"
}

# ---------------------------------------------------------------------------
# 3. Failure categories documented (at least 4 of: build, test, network, agent, state, environment)
# ---------------------------------------------------------------------------
@test "circuit-breaker-contract: at least 4 failure categories documented" {
  local section
  section=$(sed -n '/## 8.1 Circuit Breaker/,/^## [0-9]/p' "$RECOVERY_ENGINE")
  local count=0
  for category in build test network agent state environment; do
    if echo "$section" | grep -qi "$category"; then
      count=$((count + 1))
    fi
  done
  [[ $count -ge 4 ]] \
    || fail "Expected at least 4 failure categories, found $count"
}

# ---------------------------------------------------------------------------
# 4. Threshold documented
# ---------------------------------------------------------------------------
@test "circuit-breaker-contract: failure threshold is documented" {
  local section
  section=$(sed -n '/## 8.1 Circuit Breaker/,/^## [0-9]/p' "$RECOVERY_ENGINE")
  echo "$section" | grep -qi "threshold" \
    || fail "Failure threshold not documented in circuit breaker section"
}

# ---------------------------------------------------------------------------
# 5. Timeout/reset (cooldown) documented
# ---------------------------------------------------------------------------
@test "circuit-breaker-contract: cooldown or timeout/reset documented" {
  local section
  section=$(sed -n '/## 8.1 Circuit Breaker/,/^## [0-9]/p' "$RECOVERY_ENGINE")
  echo "$section" | grep -qi "cooldown\|timeout\|reset" \
    || fail "Cooldown/timeout/reset not documented in circuit breaker section"
}

# ---------------------------------------------------------------------------
# 6. Schema in state-schema.md
# ---------------------------------------------------------------------------
@test "circuit-breaker-contract: circuit_breakers schema documented in state-schema.md" {
  grep -q "circuit_breakers" "$STATE_SCHEMA" \
    || fail "circuit_breakers not found in state-schema.md"
}

# ---------------------------------------------------------------------------
# 7. Integrates with budget system
# ---------------------------------------------------------------------------
@test "circuit-breaker-contract: circuit breaker integrates with recovery budget" {
  local section
  section=$(sed -n '/## 8.1 Circuit Breaker/,/^## [0-9]/p' "$RECOVERY_ENGINE")
  echo "$section" | grep -qi "budget" \
    || fail "Budget integration not documented in circuit breaker section"
}
