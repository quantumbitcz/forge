#!/usr/bin/env bats
# Contract tests: graph enrichment patterns (14 & 15) and schema properties.

load '../helpers/test-helpers'

QUERY_PATTERNS="$PLUGIN_ROOT/shared/graph/query-patterns.md"
SCHEMA="$PLUGIN_ROOT/shared/graph/schema.md"

# ---------------------------------------------------------------------------
# 1. Pattern 14 documented with bug_fix_count
# ---------------------------------------------------------------------------
@test "graph-enrichment: Pattern 14 references bug_fix_count property" {
  [[ -f "$QUERY_PATTERNS" ]] || fail "query-patterns.md not found: $QUERY_PATTERNS"
  grep -q "bug_fix_count" "$QUERY_PATTERNS" \
    || fail "Pattern 14 must reference bug_fix_count in $QUERY_PATTERNS"
}

# ---------------------------------------------------------------------------
# 2. Pattern 15 documented with TESTS edge
# ---------------------------------------------------------------------------
@test "graph-enrichment: Pattern 15 references TESTS relationship" {
  [[ -f "$QUERY_PATTERNS" ]] || fail "query-patterns.md not found: $QUERY_PATTERNS"
  grep -q "\[:TESTS\]" "$QUERY_PATTERNS" \
    || fail "Pattern 15 must reference [:TESTS] edge in $QUERY_PATTERNS"
}

# ---------------------------------------------------------------------------
# 3. Schema has bug_fix_count on ProjectFile
# ---------------------------------------------------------------------------
@test "graph-enrichment: schema.md documents bug_fix_count on ProjectFile" {
  [[ -f "$SCHEMA" ]] || fail "schema.md not found: $SCHEMA"
  grep -q "bug_fix_count" "$SCHEMA" \
    || fail "schema.md must document bug_fix_count property for ProjectFile"
}

# ---------------------------------------------------------------------------
# 4. Schema has last_bug_fix_date on ProjectFile
# ---------------------------------------------------------------------------
@test "graph-enrichment: schema.md documents last_bug_fix_date on ProjectFile" {
  [[ -f "$SCHEMA" ]] || fail "schema.md not found: $SCHEMA"
  grep -q "last_bug_fix_date" "$SCHEMA" \
    || fail "schema.md must document last_bug_fix_date property for ProjectFile"
}

# ---------------------------------------------------------------------------
# 5. Graceful degradation documented for Pattern 14
# ---------------------------------------------------------------------------
@test "graph-enrichment: Pattern 14 documents graceful degradation" {
  [[ -f "$QUERY_PATTERNS" ]] || fail "query-patterns.md not found: $QUERY_PATTERNS"
  # Pattern 14 section must mention degradation / empty result behaviour
  awk '/^## Pattern 14/,/^## Pattern 15/' "$QUERY_PATTERNS" \
    | grep -qi "graceful degradation\|empty result\|no hotspot" \
    || fail "Pattern 14 must document graceful degradation behaviour"
}

# ---------------------------------------------------------------------------
# 6. Graceful degradation documented for Pattern 15
# ---------------------------------------------------------------------------
@test "graph-enrichment: Pattern 15 documents graceful degradation" {
  [[ -f "$QUERY_PATTERNS" ]] || fail "query-patterns.md not found: $QUERY_PATTERNS"
  # Pattern 15 section runs to end of file (last pattern)
  awk '/^## Pattern 15/,0' "$QUERY_PATTERNS" \
    | grep -qi "graceful degradation\|no.*TESTS.*edges\|returns all classes" \
    || fail "Pattern 15 must document graceful degradation behaviour"
}

# ---------------------------------------------------------------------------
# 7. fg-020-bug-investigator has neo4j-mcp in tools
# ---------------------------------------------------------------------------
@test "graph-enrichment: fg-020-bug-investigator has neo4j-mcp in tools" {
  local agent_file="$PLUGIN_ROOT/agents/fg-020-bug-investigator.md"
  [[ -f "$agent_file" ]] || fail "Agent file not found: $agent_file"
  grep -q "neo4j-mcp" "$agent_file" \
    || fail "fg-020-bug-investigator must list neo4j-mcp in tools (needed for Pattern 14 & 15 queries)"
}

# ---------------------------------------------------------------------------
# 8. fg-010-shaper has neo4j-mcp in tools
# NOTE: expected to fail until Task 2 distributes neo4j-mcp to this agent
# ---------------------------------------------------------------------------
@test "graph-enrichment: fg-010-shaper has neo4j-mcp in tools" {
  local agent_file="$PLUGIN_ROOT/agents/fg-010-shaper.md"
  [[ -f "$agent_file" ]] || fail "Agent file not found: $agent_file"
  grep -q "neo4j-mcp" "$agent_file" \
    || fail "fg-010-shaper must list neo4j-mcp in tools (risk flagging via Pattern 14)"
}

# ---------------------------------------------------------------------------
# 9. fg-200-planner has neo4j-mcp in tools
# NOTE: expected to fail until Task 2 distributes neo4j-mcp to this agent
# ---------------------------------------------------------------------------
@test "graph-enrichment: fg-200-planner has neo4j-mcp in tools" {
  local agent_file="$PLUGIN_ROOT/agents/fg-200-planner.md"
  [[ -f "$agent_file" ]] || fail "Agent file not found: $agent_file"
  grep -q "neo4j-mcp" "$agent_file" \
    || fail "fg-200-planner must list neo4j-mcp in tools (test gap analysis via Pattern 15)"
}

# ---------------------------------------------------------------------------
# 10. fg-210-validator has neo4j-mcp in tools
# NOTE: expected to fail until Task 2 distributes neo4j-mcp to this agent
# ---------------------------------------------------------------------------
@test "graph-enrichment: fg-210-validator has neo4j-mcp in tools" {
  local agent_file="$PLUGIN_ROOT/agents/fg-210-validator.md"
  [[ -f "$agent_file" ]] || fail "Agent file not found: $agent_file"
  grep -q "neo4j-mcp" "$agent_file" \
    || fail "fg-210-validator must list neo4j-mcp in tools (decision traceability queries)"
}

# ---------------------------------------------------------------------------
# 11. fg-400-quality-gate has neo4j-mcp in tools
# NOTE: expected to fail until Task 2 distributes neo4j-mcp to this agent
# ---------------------------------------------------------------------------
@test "graph-enrichment: fg-400-quality-gate has neo4j-mcp in tools" {
  local agent_file="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
  [[ -f "$agent_file" ]] || fail "Agent file not found: $agent_file"
  grep -q "neo4j-mcp" "$agent_file" \
    || fail "fg-400-quality-gate must list neo4j-mcp in tools (hotspot risk flagging via Pattern 14)"
}
