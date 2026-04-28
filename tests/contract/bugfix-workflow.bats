#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
  ORCHESTRATOR_ALL="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
  STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
  STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
  STATE_SCHEMA_FIELDS="$PLUGIN_ROOT/shared/state-schema-fields.md"
  BUG_INVESTIGATOR="$PLUGIN_ROOT/agents/fg-020-bug-investigator.md"
  FORGE_SKILL="$PLUGIN_ROOT/skills/forge/SKILL.md"
  RETROSPECTIVE="$PLUGIN_ROOT/agents/fg-700-retrospective.md"
}

# Extract a `### Subcommand: <name>` block from skills/forge/SKILL.md.
# Captures lines from `### Subcommand: <name>` (inclusive) until the next
# `### Subcommand:` heading or top-level `## ` heading.
_forge_subcommand_block() {
  awk -v name="$1" '
    $0 ~ "^### Subcommand: " name "$" { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$FORGE_SKILL"
}

# --- Agent ---
@test "bugfix: fg-020-bug-investigator agent exists" {
  [ -f "$BUG_INVESTIGATOR" ]
}

@test "bugfix: fg-020-bug-investigator has valid frontmatter" {
  grep -q "^name: fg-020-bug-investigator$" "$BUG_INVESTIGATOR"
  grep -q "^tools:" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator has neo4j-mcp in tools" {
  grep -q "neo4j-mcp" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator has AskUserQuestion in tools" {
  grep -q "AskUserQuestion" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator documents INVESTIGATE phase" {
  grep -q "INVESTIGATE\|Phase 1" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator documents REPRODUCE phase" {
  grep -q "REPRODUCE\|Phase 2" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator has Forbidden Actions" {
  grep -q "Forbidden Actions" "$BUG_INVESTIGATOR"
}

@test "bugfix: fg-020-bug-investigator documents max 3 reproduction attempts" {
  grep -q "3 attempt\|max 3\|3 reproduction" "$BUG_INVESTIGATOR"
}

# --- Skill (consolidated /forge skill, fix subcommand) ---
@test "bugfix: forge skill exists" {
  [ -f "$FORGE_SKILL" ]
}

@test "bugfix: forge skill has valid frontmatter" {
  grep -q "^name: forge$" "$FORGE_SKILL"
}

@test "bugfix: forge skill documents fix subcommand" {
  grep -q '^### Subcommand: fix$' "$FORGE_SKILL"
}

@test "bugfix: fix subcommand documents kanban ticket input" {
  _forge_subcommand_block fix | grep -q "kanban\|ticket"
}

@test "bugfix: fix subcommand documents Linear input" {
  _forge_subcommand_block fix | grep -q "linear\|Linear\|--linear"
}

@test "bugfix: fix subcommand dispatches orchestrator with bugfix mode" {
  _forge_subcommand_block fix | grep -qi "mode.*bugfix\|bugfix.*mode"
}

# --- Orchestrator ---
@test "bugfix: orchestrator detects bugfix mode prefix" {
  grep -q "bugfix:\|fix:" $ORCHESTRATOR_ALL
}

@test "bugfix: orchestrator has bugfix fields in state init" {
  grep -q '"bugfix"' "$ORCHESTRATOR"
}

@test "bugfix: orchestrator dispatches fg-020-bug-investigator" {
  grep -q "fg-020-bug-investigator" $ORCHESTRATOR_ALL
}

@test "bugfix: orchestrator has bugfix-specific validation perspectives" {
  grep -q "root_cause_validity\|fix_scope\|regression_risk" $ORCHESTRATOR_ALL
}

@test "bugfix: orchestrator has reduced review batch for bugfix" {
  grep -qi "bugfix.*review\|reduced.*batch\|bugfix review" $ORCHESTRATOR_ALL
}

@test "bugfix: bugfix reduced batch includes fg-410-code-reviewer" {
  # Section 9.0a should dispatch fg-410-code-reviewer alongside security
  grep -q "fg-410-code-reviewer" "$ORCHESTRATOR"
}

# --- Stage Contract ---
@test "bugfix: stage contract has Bugfix Mode section" {
  grep -q "Bugfix Mode" "$STAGE_CONTRACT"
}

@test "bugfix: stage contract documents INVESTIGATE stage" {
  grep -q "INVESTIGATE" "$STAGE_CONTRACT"
}

@test "bugfix: stage contract documents REPRODUCE stage" {
  grep -q "REPRODUCE" "$STAGE_CONTRACT"
}

@test "bugfix: stage contract documents unreproducible escalation" {
  grep -q "unreproducible\|unresolvable" "$STAGE_CONTRACT"
}

# --- State Schema ---
@test "bugfix: state schema documents bugfix.source field" {
  grep -qh "bugfix\.source\|bugfix.source" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"
}

@test "bugfix: state schema documents bugfix.reproduction fields" {
  grep -qh "bugfix\.reproduction\|bugfix.reproduction" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"
}

@test "bugfix: state schema documents bugfix.root_cause fields" {
  grep -qh "bugfix\.root_cause\|bugfix.root_cause" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"
}

@test "bugfix: state schema lists bugfix as valid mode" {
  grep -qh "bugfix" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS"
}

# --- Retrospective ---
@test "bugfix: retrospective documents bug pattern tracking" {
  grep -qi "bug pattern\|Bug Pattern" "$RETROSPECTIVE"
}

@test "bugfix: retrospective tracks root cause category" {
  grep -q "root.cause.category\|Root cause category\|root_cause" "$RETROSPECTIVE"
}

# --- forge run subcommand ---
@test "bugfix: forge run subcommand accepts bugfix: prefix" {
  _forge_subcommand_block run | grep -q "bugfix:"
}
