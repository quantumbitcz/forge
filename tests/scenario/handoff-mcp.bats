#!/usr/bin/env bats

load '../lib/bats-support/load'
load '../lib/bats-assert/load'

@test "MCP server exposes forge_list_handoffs tool" {
  run grep -q "forge_list_handoffs" shared/mcp-server/forge-mcp-server.py
  assert_success
}

@test "MCP server exposes forge_get_handoff tool" {
  run grep -q "forge_get_handoff" shared/mcp-server/forge-mcp-server.py
  assert_success
}
