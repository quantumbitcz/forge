#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  SKILLS_DIR="$BATS_TEST_DIRNAME/../../../skills"
}

@test "skill-mcp-detection: forge-run detects MCPs" {
  run grep -qi 'MCP\|mcp\|Linear\|Playwright\|Context7' "$SKILLS_DIR/forge-run/SKILL.md"
  assert_success
}

@test "skill-mcp-detection: forge-fix detects MCPs" {
  run grep -qi 'MCP\|mcp' "$SKILLS_DIR/forge-fix/SKILL.md"
  assert_success
}

@test "skill-mcp-detection: forge-shape detects MCPs" {
  run grep -qi 'MCP\|mcp' "$SKILLS_DIR/forge-shape/SKILL.md"
  assert_success
}

@test "skill-mcp-detection: graph skills check Neo4j availability" {
  run grep -qi 'neo4j\|docker\|health' "$SKILLS_DIR/graph-init/SKILL.md"
  assert_success
}
