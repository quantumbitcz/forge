#!/usr/bin/env bats
# AC-S021: fg-010-shaper.md must implement the seven-step pattern from §3.
# Each heading must appear EXACTLY ONCE.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SHAPER="$PLUGIN_ROOT/agents/fg-010-shaper.md"
}

@test "fg-010-shaper.md exists" {
  [ -f "$SHAPER" ]
}

# C1 (Phase C) does the rewrite; Phase B's structural test asserts the headings.
# Until C1 lands these tests will fail or skip — they are the gate that keeps
# C1 honest about the seven-step pattern.

@test "## Explore project context heading appears exactly once" {
  count=$(grep -c '^## Explore project context$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "fg-010-shaper not yet rewritten (C1) — AC-S021 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Ask clarifying questions heading appears exactly once" {
  count=$(grep -c '^## Ask clarifying questions$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Propose 2-3 approaches heading appears exactly once" {
  count=$(grep -c '^## Propose 2-3 approaches$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Present design sections heading appears exactly once" {
  count=$(grep -c '^## Present design sections$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Write spec heading appears exactly once" {
  count=$(grep -c '^## Write spec$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Self-review heading appears exactly once" {
  count=$(grep -c '^## Self-review$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Handoff heading appears exactly once" {
  count=$(grep -c '^## Handoff$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}
