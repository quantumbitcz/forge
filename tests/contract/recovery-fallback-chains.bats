#!/usr/bin/env bats
# Contract tests: recovery engine fallback chains
# Validates the fallback chain documentation in recovery-engine.md.

load '../helpers/test-helpers'

RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
STRATEGIES_DIR="$PLUGIN_ROOT/shared/recovery/strategies"

# ---------------------------------------------------------------------------
# 1. All 7 categories have chains defined
# ---------------------------------------------------------------------------
@test "recovery-fallback: all 7 categories have chains defined" {
  local section
  section=$(sed -n '/^## 10\. Fallback Chains/,/^## [0-9]/p' "$RECOVERY_ENGINE")

  for category in TRANSIENT TOOL_FAILURE AGENT_FAILURE STATE_CORRUPTION EXTERNAL_DEPENDENCY RESOURCE_EXHAUSTION UNRECOVERABLE; do
    echo "$section" | grep -q "$category" \
      || fail "Category '$category' not found in fallback chains section"
  done
}

# ---------------------------------------------------------------------------
# 2. UNRECOVERABLE has no fallbacks
# ---------------------------------------------------------------------------
@test "recovery-fallback: UNRECOVERABLE has no fallbacks" {
  local section
  section=$(sed -n '/^## 10\. Fallback Chains/,/^## [0-9]/p' "$RECOVERY_ENGINE")

  local unrecoverable_row
  unrecoverable_row=$(echo "$section" | grep "UNRECOVERABLE")

  # UNRECOVERABLE should only have graceful-stop and "—" for fallbacks
  echo "$unrecoverable_row" | grep -q "graceful-stop" \
    || fail "UNRECOVERABLE primary should be graceful-stop"

  # Count non-dash entries after Primary — should be 0 (all fallbacks are —)
  local fallback_count
  fallback_count=$(echo "$unrecoverable_row" | awk -F'|' '{
    count=0;
    # Columns: empty | Category | Primary | Fallback 1 | Fallback 2 | empty
    for(i=4; i<=5; i++) {
      gsub(/^ +| +$/, "", $i);
      if ($i != "—" && $i != "" && $i != "-") count++
    }
    print count
  }')
  [[ "$fallback_count" -eq 0 ]] \
    || fail "UNRECOVERABLE should have no fallback strategies, found $fallback_count"
}

# ---------------------------------------------------------------------------
# 3. All fallback strategies reference valid strategy names
# ---------------------------------------------------------------------------
@test "recovery-fallback: all fallback strategies reference valid strategy names" {
  local section
  section=$(sed -n '/^## 10\. Fallback Chains/,/^## [0-9]/p' "$RECOVERY_ENGINE")

  # Extract all strategy names from the fallback table (skip headers and —)
  local strategies
  strategies=$(echo "$section" | grep -E '^\|' | grep -v '^\| Category' | grep -v '^\|---' \
    | awk -F'|' '{
      for(i=3; i<=5; i++) {
        gsub(/^ +| +$/, "", $i);
        # Strip weight suffix like "(0.5)"
        gsub(/ *\([0-9.]+\)/, "", $i);
        if ($i != "—" && $i != "" && $i != "-") print $i
      }
    }' | sort -u)

  local missing=0
  while IFS= read -r strategy; do
    [[ -z "$strategy" ]] && continue
    if [[ ! -f "$STRATEGIES_DIR/${strategy}.md" ]]; then
      echo "MISSING strategy file: $STRATEGIES_DIR/${strategy}.md"
      missing=$((missing + 1))
    fi
  done <<< "$strategies"

  [[ $missing -eq 0 ]] || fail "$missing fallback strategies reference non-existent strategy files"
}

# ---------------------------------------------------------------------------
# 4. Fallback chain section documented
# ---------------------------------------------------------------------------
@test "recovery-fallback: fallback chain section documented" {
  grep -q "## 10\. Fallback Chains" "$RECOVERY_ENGINE" \
    || fail "Section 10 'Fallback Chains' heading not found"
}

# ---------------------------------------------------------------------------
# 5. Fallback rules documented
# ---------------------------------------------------------------------------
@test "recovery-fallback: all 5 fallback rules documented" {
  local section
  section=$(sed -n '/^## 10\. Fallback Chains/,/^## [0-9]/p' "$RECOVERY_ENGINE")

  # Rule 1: independent weight consumption
  echo "$section" | grep -qi "weight.*independently\|own weight" \
    || fail "Rule 1 (independent weight) not documented"

  # Rule 2: budget exceeded skip
  echo "$section" | grep -qi "budget.*exceeded\|budget.*skip" \
    || fail "Rule 2 (budget exceeded skip) not documented"

  # Rule 3: no duplicate strategy
  echo "$section" | grep -qi "same strategy.*never\|never.*twice\|never.*applied twice" \
    || fail "Rule 3 (no duplicate strategy) not documented"

  # Rule 4: circuit breaker checks
  echo "$section" | grep -qi "circuit breaker" \
    || fail "Rule 4 (circuit breaker) not documented"

  # Rule 5: max depth 2
  echo "$section" | grep -qi "2 fallback\|depth.*2\|maximum.*2" \
    || fail "Rule 5 (max depth 2) not documented"
}
