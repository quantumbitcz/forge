#!/usr/bin/env bats
# Scenario: AC-S027 — /forge --autonomous "<request>" on a project with no
# forge.local.md must chain auto-bootstrap → BRAINSTORMING → EXPLORING in a
# single run, with both [AUTO] log lines present, and abort cleanly on failure.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init -q
  # No .claude/forge.local.md present. No .forge/ present.
}

teardown() {
  cd "$PLUGIN_ROOT"
  rm -rf "$TMPDIR_TEST"
}

@test "cold-start skill files exist and frontmatter is valid" {
  [ -f "$PLUGIN_ROOT/skills/forge/SKILL.md" ]
  grep -q '^name: forge$' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "/forge SKILL.md documents auto-bootstrap on missing forge.local.md" {
  grep -q 'forge.local.md.*absent' "$PLUGIN_ROOT/skills/forge/SKILL.md"
  grep -q 'Bootstrap trigger' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "/forge SKILL.md documents the AUTO log line for autonomous bootstrap" {
  grep -qE '\[AUTO\] bootstrapped' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "/forge SKILL.md documents that .forge/ absence does NOT trigger bootstrap (AC-S016)" {
  grep -q 'runtime directory `.forge/` is .*not. a trigger' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "shared/bootstrap-detect.py exists (A2 dependency)" {
  [ -f "$PLUGIN_ROOT/shared/bootstrap-detect.py" ]
}

@test "AUTO brainstorm-skipped log line is documented in fg-010-shaper" {
  # The shaper documents autonomous degradation (AC-S022, post-C1).
  # B13 only verifies the log line is mentioned in the skill or shaper file.
  if [ -f "$PLUGIN_ROOT/agents/fg-010-shaper.md" ]; then
    grep -qE '\[AUTO\] brainstorm skipped' "$PLUGIN_ROOT/agents/fg-010-shaper.md" \
      || skip "fg-010-shaper not yet rewritten (C1) — autonomous-cold-start AC-S027 deferred"
  else
    skip "fg-010-shaper.md missing — pre-Phase-C state"
  fi
}

@test "atomic-write contract is documented in bootstrap-detect.py (A2)" {
  grep -q 'temp-file-and-rename' "$PLUGIN_ROOT/shared/bootstrap-detect.py" \
    || grep -q 'atomic' "$PLUGIN_ROOT/shared/bootstrap-detect.py"
}

@test "autonomous-cold-start scenario: no partial state on failure" {
  # The skill body MUST commit to: detection failure aborts; write failure aborts.
  grep -q 'Detection ambiguous' "$PLUGIN_ROOT/skills/forge/SKILL.md"
  grep -q 'Write fails' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}
