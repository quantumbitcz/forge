#!/usr/bin/env bats
# /forge dispatch grammar — 11 verb tests + 3 NL fallback tests.
# Per AC-S006, AC-S007, AC-S010.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  SKILL_FILE="$PLUGIN_ROOT/skills/forge/SKILL.md"
}

# These tests assert structural properties of the SKILL.md dispatch
# table — they verify each verb has a documented dispatch target. Full
# end-to-end runtime tests are out of scope for unit-level bats.

@test "verb 'run' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: run' "$SKILL_FILE"
}

@test "verb 'fix' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: fix' "$SKILL_FILE"
}

@test "verb 'sprint' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: sprint' "$SKILL_FILE"
}

@test "verb 'review' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: review' "$SKILL_FILE"
}

@test "verb 'verify' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: verify' "$SKILL_FILE"
}

@test "verb 'deploy' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: deploy' "$SKILL_FILE"
}

@test "verb 'commit' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: commit' "$SKILL_FILE"
}

@test "verb 'migrate' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: migrate' "$SKILL_FILE"
}

@test "verb 'bootstrap' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: bootstrap' "$SKILL_FILE"
}

@test "verb 'docs' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: docs' "$SKILL_FILE"
}

@test "verb 'audit' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: audit' "$SKILL_FILE"
}

@test "NL fallback path is documented (vague-input case)" {
  # AC-S007: vague free-text falls through to intent classifier and
  # defaults to run mode. The skill must reference shared/intent-classification.md.
  grep -q 'shared/intent-classification.md' "$SKILL_FILE"
  grep -q 'NL fallback' "$SKILL_FILE"
}

@test "NL fallback path: classifier-resolved input dispatches to verb" {
  # The dispatch rules must mention falling through to NL classifier
  # when the first token is not a known verb.
  grep -q 'fall through to the NL-classifier' "$SKILL_FILE"
}

@test "test_unknown_verb_falls_through (no 'did you mean' message)" {
  # AC-S010: unknown verbs MUST NOT produce "did you mean" output.
  ! grep -qi 'did you mean' "$SKILL_FILE"
  # And the skill must explicitly document silent fall-through:
  grep -q 'silently classify' "$SKILL_FILE"
}

@test "ambiguous-flag-positioning is documented as an error (AC-S007)" {
  # AC-S007: third NL-fallback case — flags after the free-text arg
  # must fail fast with usage. The skill body documents this rule.
  grep -q 'Flags must appear BEFORE the free-text argument' "$SKILL_FILE"
  grep -q 'fail fast with usage' "$SKILL_FILE"
}
