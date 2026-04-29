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

@test "skill-mcp-detection: forge run subcommand detects MCPs" {
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge/SKILL.md' run | grep -qi 'MCP\|mcp\|Linear\|Playwright\|Context7'"
  assert_success
}

@test "skill-mcp-detection: forge fix subcommand detects MCPs" {
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge/SKILL.md' fix | grep -qi 'MCP\|mcp'"
  assert_success
}

@test "skill-mcp-detection: forge run subcommand mentions MCPs (shape via run)" {
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge/SKILL.md' run | grep -qi 'MCP\|mcp'"
  assert_success
}

@test "skill-mcp-detection: forge-admin graph subcommand checks Neo4j availability" {
  # forge-graph-init consolidated into /forge-admin graph.
  run bash -c "$(declare -f _subcommand_block); _subcommand_block '$SKILLS_DIR/forge-admin/SKILL.md' graph | grep -qi 'neo4j\|docker\|health'"
  assert_success
}
