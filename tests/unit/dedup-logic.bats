#!/usr/bin/env bats
# Unit tests: finding deduplication logic — validates the dedup algorithm
# documented in scoring.md via the dedup-helper.sh implementation.

load '../helpers/test-helpers'

DEDUP="$PLUGIN_ROOT/tests/helpers/dedup-helper.sh"
SCORING="$PLUGIN_ROOT/shared/scoring.md"

compute_score() {
  local critical="${1:-0}" warning="${2:-0}" info="${3:-0}"
  local raw=$(( 100 - 20 * critical - 5 * warning - 2 * info ))
  if [[ $raw -lt 0 ]]; then echo 0; else echo "$raw"; fi
}

@test "dedup: identical findings from 2 agents, keep highest severity" {
  local input
  input=$(printf '%s\n%s\n' \
    "src/User.kt:42 | ARCH-BOUNDARY | WARNING | crosses boundary | move to shared" \
    "src/User.kt:42 | ARCH-BOUNDARY | CRITICAL | crosses boundary | move to shared")
  run bash -c "echo '$input' | bash '$DEDUP'"
  assert_success
  local line_count
  line_count=$(echo "$output" | grep -c "ARCH-BOUNDARY" || true)
  [[ $line_count -eq 1 ]] || fail "Expected 1 deduplicated finding, got $line_count"
  echo "$output" | grep -q "CRITICAL" || fail "Expected CRITICAL severity to survive"
}

@test "dedup: identical location, different categories, both kept" {
  local input
  input=$(printf '%s\n%s\n' \
    "src/User.kt:42 | ARCH-BOUNDARY | WARNING | arch issue | fix arch" \
    "src/User.kt:42 | SEC-INJECTION | CRITICAL | security issue | fix sec")
  run bash -c "echo '$input' | bash '$DEDUP'"
  assert_success
  local line_count
  line_count=$(echo "$output" | grep -c -E "ARCH-BOUNDARY|SEC-INJECTION" || true)
  [[ $line_count -eq 2 ]] || fail "Expected 2 findings (different categories), got $line_count"
}

@test "dedup: same key, keep longest description" {
  local short_msg="short msg"
  local long_msg="this is a much longer and more detailed description of the issue found"
  local input
  input=$(printf '%s\n%s\n' \
    "src/User.kt:42 | ARCH-BOUNDARY | WARNING | $short_msg | hint" \
    "src/User.kt:42 | ARCH-BOUNDARY | WARNING | $long_msg | hint")
  run bash -c "echo '$input' | bash '$DEDUP'"
  assert_success
  echo "$output" | grep -q "$long_msg" || fail "Expected longest description to survive"
}

@test "dedup: SCOUT-* excluded from dedup pass" {
  local input
  input=$(printf '%s\n%s\n' \
    "src/User.kt:42 | SCOUT-IMPORT-UNUSED | INFO | unused import | remove" \
    "src/User.kt:42 | QUAL-IMPORT-UNUSED | WARNING | unused import | remove")
  run bash -c "echo '$input' | bash '$DEDUP'"
  assert_success
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')
  [[ $line_count -eq 2 ]] || fail "Expected 2 findings (SCOUT preserved alongside non-SCOUT), got $line_count"
  echo "$output" | grep -q "SCOUT-IMPORT" || fail "SCOUT finding should be preserved"
  echo "$output" | grep -q "QUAL-IMPORT" || fail "Non-SCOUT finding should be preserved"
}

@test "dedup: multi-component dedup uses component prefix" {
  local input
  input=$(printf '%s\n%s\n' \
    "backend | src/User.kt:42 | ARCH-BOUNDARY | WARNING | crosses boundary | fix" \
    "frontend | src/User.kt:42 | ARCH-BOUNDARY | WARNING | crosses boundary | fix")
  run bash -c "echo '$input' | bash '$DEDUP' multi"
  assert_success
  local line_count
  line_count=$(echo "$output" | grep -c "ARCH-BOUNDARY" || true)
  [[ $line_count -eq 2 ]] || fail "Expected 2 findings (different components), got $line_count"
}

@test "dedup: single-component omits component from key" {
  local input
  input=$(printf '%s\n%s\n' \
    "src/User.kt:42 | ARCH-BOUNDARY | WARNING | issue A | hint A" \
    "src/User.kt:42 | ARCH-BOUNDARY | CRITICAL | issue B | hint B")
  run bash -c "echo '$input' | bash '$DEDUP'"
  assert_success
  local line_count
  line_count=$(echo "$output" | grep -c "ARCH-BOUNDARY" || true)
  [[ $line_count -eq 1 ]] || fail "Expected 1 deduplicated finding, got $line_count"
}

@test "dedup: findings at different lines in same file NOT deduped" {
  local input
  input=$(printf '%s\n%s\n' \
    "src/User.kt:42 | ARCH-BOUNDARY | WARNING | issue at 42 | fix" \
    "src/User.kt:43 | ARCH-BOUNDARY | WARNING | issue at 43 | fix")
  run bash -c "echo '$input' | bash '$DEDUP'"
  assert_success
  local line_count
  line_count=$(echo "$output" | grep -c "ARCH-BOUNDARY" || true)
  [[ $line_count -eq 2 ]] || fail "Expected 2 findings (different lines), got $line_count"
}

@test "dedup: score computed from deduplicated set" {
  local input
  input=$(printf '%s\n%s\n%s\n' \
    "src/User.kt:42 | ARCH-BOUNDARY | WARNING | issue | fix" \
    "src/User.kt:42 | ARCH-BOUNDARY | CRITICAL | same issue | fix" \
    "src/User.kt:99 | SEC-INJECTION | WARNING | sql injection | use parameterized")
  run bash -c "echo '$input' | bash '$DEDUP'"
  assert_success
  local crit_count warn_count
  crit_count=$(echo "$output" | grep -c "CRITICAL" || true)
  warn_count=$(echo "$output" | grep -c "WARNING" || true)
  local score
  score=$(compute_score "$crit_count" "$warn_count" 0)
  [[ "$score" -eq 75 ]] || fail "Expected score 75 from deduped set (1C+1W), got $score"
}

@test "dedup: empty input produces empty output" {
  run bash -c "echo '' | bash '$DEDUP'"
  assert_success
  local trimmed
  trimmed=$(echo "$output" | tr -d '[:space:]')
  [[ -z "$trimmed" ]] || fail "Expected empty output, got: $output"
}

@test "dedup: dedup key (component, file, line, category) documented in scoring.md" {
  grep -q "component, file, line, category" "$SCORING" \
    || fail "Dedup key not documented in scoring.md"
}
