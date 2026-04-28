#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

# Extract a `### Subcommand: <name>` block from a consolidated SKILL.md.
_subcommand_block() {
  local skill_file="$1" name="$2"
  awk -v name="$name" '
    $0 ~ "^### Subcommand: " name "$" { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$skill_file"
}

@test "skill-prerequisites: parent /forge skill documents shared prerequisites" {
  # Post-Mega-B: prerequisites (git repo, forge.local.md presence) live in
  # the shared prerequisites block at the top of skills/forge/SKILL.md, not
  # duplicated per-subcommand. The block applies to every subcommand.
  run grep -qiE 'Shared prerequisites|forge\.local\.md|git rev-parse|STOP' "$SKILLS_DIR/forge/SKILL.md"
  assert_success
}

@test "skill-prerequisites: forge skill checks for existing config" {
  run grep -qi 'forge.local\|existing\|already' "$SKILLS_DIR/forge/SKILL.md"
  assert_success
}

@test "skill-prerequisites: forge-admin recover subcommand checks for state.json" {
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge-admin/SKILL.md' recover | grep -qi 'state\.json\|checkpoint\|aborted'"
  assert_success
}

@test "skill-prerequisites: forge deploy subcommand parses environment input" {
  # Post-Mega-B: dirty-tree gating moved into fg-620-deploy-verifier and the
  # underlying deploy tooling (kubectl/helm/argocd) configured via
  # forge.local.md. The skill body just parses the environment and
  # dispatches; the verifier owns the pre-deploy guardrails.
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge/SKILL.md' deploy | grep -qiE 'staging|production|preview|environment'"
  assert_success
}
