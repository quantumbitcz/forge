#!/usr/bin/env bats
# Unit: pricing table in forge-token-tracker.sh matches Anthropic 2026-04-22 rates.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-token-tracker.sh"

@test "pricing: haiku input = 1.00 per MTok" {
  run grep -E '"haiku":\s*\{"input":\s*1\.00' "$SCRIPT"
  assert_success
}

@test "pricing: haiku output = 5.00 per MTok" {
  run grep -E '"haiku":[^}]*"output":\s*5\.00' "$SCRIPT"
  assert_success
}

@test "pricing: sonnet input = 3.00 per MTok" {
  run grep -E '"sonnet":\s*\{"input":\s*3\.00' "$SCRIPT"
  assert_success
}

@test "pricing: sonnet output = 15.00 per MTok" {
  run grep -E '"sonnet":[^}]*"output":\s*15\.00' "$SCRIPT"
  assert_success
}

@test "pricing: opus input = 5.00 per MTok (Opus 4.7, NOT legacy 15.00)" {
  run grep -E '"opus":\s*\{"input":\s*5\.00' "$SCRIPT"
  assert_success
}

@test "pricing: opus output = 25.00 per MTok (Opus 4.7, NOT legacy 75.00)" {
  run grep -E '"opus":[^}]*"output":\s*25\.00' "$SCRIPT"
  assert_success
}

@test "pricing: header comment cites 2026-04-22 verification date" {
  run grep "2026-04-22" "$SCRIPT"
  assert_success
}
