#!/usr/bin/env bash
# Phase 13 — memory decay eval harness.
# Usage: ./tests/evals/memory_decay_eval.sh
# Runs the dry-run-recompute CLI against the fixture grid and asserts each
# item lands in the expected tier (fresh → HIGH, 1× HL → MEDIUM, 3× HL → ARCHIVED).
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")" && pwd)/fixtures/memory_decay"
NOW="2026-04-19T12:00:00Z"

output=$(python3 -m hooks._py.memory_decay --dry-run-recompute "$FIXTURE_DIR" --now "$NOW")

assert_tier() {
  local id="$1" expected="$2"
  local line
  line=$(printf '%s\n' "$output" | awk -v id="$id" '$1==id {print $2}')
  if [ "$line" != "$expected" ]; then
    echo "FAIL: $id expected $expected, got '$line'"
    exit 1
  fi
  echo "OK: $id → $expected"
}

# Fresh (Δt=0) → full base (0.75) → HIGH (per thresholds, c >= 0.75 is HIGH).
assert_tier auto_fresh HIGH
assert_tier cross_fresh HIGH
assert_tier canon_fresh HIGH
# One half-life → base/2 = 0.375 → LOW.
assert_tier auto_mid LOW
assert_tier cross_mid LOW
assert_tier canon_mid LOW
# Three half-lives → base/8 = 0.09375 → ARCHIVED.
assert_tier auto_stale ARCHIVED
assert_tier cross_stale ARCHIVED
assert_tier canon_stale ARCHIVED
# Legacy record: migrator stamps now → fresh → HIGH (warm start).
assert_tier legacy_high HIGH
# FP victim: 2 days old, auto-discovered, base 0.60.
# c = 0.60 * 2^(-2/14) ≈ 0.5434 → MEDIUM.
assert_tier fp_victim MEDIUM

echo "All tier assertions passed."
