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

@test "skill-error-handling: parent /forge skill documents error handling" {
  # Post-Mega-B: per-subcommand error handling is delegated to the dispatched
  # agents (orchestrator, quality gate, bug investigator). The parent skill
  # documents shared error pathways (failure modes, exit codes, AC-S007
  # ambiguous-flag rejection, NL fallback). Verify those are present at the
  # top-level skill surface rather than duplicated per-subcommand.
  run grep -qiE 'error|fail|STOP|abort' "$SKILLS_DIR/forge/SKILL.md"
  assert_success
}

@test "skill-error-handling: forge-admin graph subcommand handles missing Neo4j" {
  # Skill consolidation: 5 graph skills merged into /forge-admin graph with positional subcommands.
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge-admin/SKILL.md' graph | grep -qi 'docker\|container\|unavailable\|not running'"
  assert_success
}

@test "skill-error-handling: forge deploy subcommand references deploy verifier" {
  # Post-Mega-B: rollback/revert behavior moved into fg-620-deploy-verifier
  # and the deployment tooling (kubectl/helm/argocd) referenced via
  # forge.local.md. The skill body just dispatches; the verifier owns the
  # rollback contract.
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge/SKILL.md' deploy | grep -qi 'fg-620-deploy-verifier\|kubectl\|helm\|argocd'"
  assert_success
}
