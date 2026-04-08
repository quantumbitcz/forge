#!/usr/bin/env bats
# Contract tests for shared/intent-classification.md

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
INTENT="$ROOT/shared/intent-classification.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "intent-classification: document exists" {
  [ -f "$INTENT" ]
}

# ---------------------------------------------------------------------------
# 2. Classification table covers all pipeline modes
# ---------------------------------------------------------------------------
@test "intent-classification: all pipeline modes documented" {
  for mode in bugfix migration bootstrap multi-feature vague testing documentation refactor performance single-feature; do
    grep -qi "$mode" "$INTENT" || fail "Missing mode: $mode"
  done
}

# ---------------------------------------------------------------------------
# 3. Classification priority order documented
# ---------------------------------------------------------------------------
@test "intent-classification: classification priority order documented" {
  grep -q "## Classification Priority" "$INTENT"
  grep -q "precedence" "$INTENT"
}

# ---------------------------------------------------------------------------
# 4. Bugfix routing documented
# ---------------------------------------------------------------------------
@test "intent-classification: bugfix routes to fg-020-bug-investigator" {
  grep -q "fg-020-bug-investigator" "$INTENT"
}

# ---------------------------------------------------------------------------
# 5. Migration routing documented
# ---------------------------------------------------------------------------
@test "intent-classification: migration routes to fg-160" {
  grep -q "fg-160" "$INTENT"
}

# ---------------------------------------------------------------------------
# 6. Bootstrap routing documented
# ---------------------------------------------------------------------------
@test "intent-classification: bootstrap routes to fg-050" {
  grep -q "fg-050" "$INTENT"
}

# ---------------------------------------------------------------------------
# 7. Multi-feature decomposition routing documented
# ---------------------------------------------------------------------------
@test "intent-classification: multi-feature routes to fg-015 and fg-090" {
  grep -q "fg-015" "$INTENT"
  grep -q "fg-090" "$INTENT"
}

# ---------------------------------------------------------------------------
# 8. Vague routing documented
# ---------------------------------------------------------------------------
@test "intent-classification: vague routes to fg-010-shaper" {
  grep -q "fg-010" "$INTENT"
}

# ---------------------------------------------------------------------------
# 9. Signal detection section exists
# ---------------------------------------------------------------------------
@test "intent-classification: signal detection rules documented" {
  grep -q "## Signal Detection Rules" "$INTENT"
}

# ---------------------------------------------------------------------------
# 10. Explicit prefix override takes precedence
# ---------------------------------------------------------------------------
@test "intent-classification: explicit prefix override documented as highest priority" {
  grep -qi "explicit prefix.*override.*always wins\|override.*highest" "$INTENT"
}

# ---------------------------------------------------------------------------
# 11. Feature completeness check for vague detection documented
# ---------------------------------------------------------------------------
@test "intent-classification: feature completeness check documented" {
  grep -qi "completeness\|actors.*entities.*surface.*criteria" "$INTENT"
}
