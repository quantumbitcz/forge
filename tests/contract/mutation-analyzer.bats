#!/usr/bin/env bats
# Contract tests: fg-510-mutation-analyzer agent existence and required sections.

load '../helpers/test-helpers'

AGENT="$PLUGIN_ROOT/agents/fg-510-mutation-analyzer.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "mutation-analyzer: agent file exists" {
  [ -f "$AGENT" ] || fail "agents/fg-510-mutation-analyzer.md not found"
}

# ---------------------------------------------------------------------------
# 2. Frontmatter: correct name
# ---------------------------------------------------------------------------
@test "mutation-analyzer: has correct name in frontmatter" {
  local name_value
  name_value="$(grep -E '^name:' "$AGENT" | head -1 | sed 's/^name:[[:space:]]*//')"
  [[ "$name_value" == "fg-510-mutation-analyzer" ]] \
    || fail "Expected name 'fg-510-mutation-analyzer', got '$name_value'"
}

# ---------------------------------------------------------------------------
# 3. Frontmatter: has description
# ---------------------------------------------------------------------------
@test "mutation-analyzer: has description in frontmatter" {
  grep -qE '^description:' "$AGENT" \
    || fail "Missing description: field in frontmatter"
}

# ---------------------------------------------------------------------------
# 4. Frontmatter: has tools
# ---------------------------------------------------------------------------
@test "mutation-analyzer: has tools in frontmatter" {
  grep -qE '^tools:' "$AGENT" \
    || fail "Missing tools: field in frontmatter"
}

# ---------------------------------------------------------------------------
# 5. Documents all 4 mutation categories
# ---------------------------------------------------------------------------
@test "mutation-analyzer: documents boundary_conditions category" {
  grep -qi "boundary_conditions" "$AGENT" \
    || fail "boundary_conditions mutation category not documented"
}

@test "mutation-analyzer: documents null_handling category" {
  grep -qi "null_handling" "$AGENT" \
    || fail "null_handling mutation category not documented"
}

@test "mutation-analyzer: documents error_paths category" {
  grep -qi "error_paths" "$AGENT" \
    || fail "error_paths mutation category not documented"
}

@test "mutation-analyzer: documents logic_inversions category" {
  grep -qi "logic_inversions" "$AGENT" \
    || fail "logic_inversions mutation category not documented"
}

# ---------------------------------------------------------------------------
# 6. Documents all 3 finding categories
# ---------------------------------------------------------------------------
@test "mutation-analyzer: documents TEST-MUTATION-SURVIVE finding" {
  grep -q "TEST-MUTATION-SURVIVE" "$AGENT" \
    || fail "TEST-MUTATION-SURVIVE finding category not documented"
}

@test "mutation-analyzer: documents TEST-MUTATION-TIMEOUT finding" {
  grep -q "TEST-MUTATION-TIMEOUT" "$AGENT" \
    || fail "TEST-MUTATION-TIMEOUT finding category not documented"
}

@test "mutation-analyzer: documents TEST-MUTATION-EQUIVALENT finding" {
  grep -q "TEST-MUTATION-EQUIVALENT" "$AGENT" \
    || fail "TEST-MUTATION-EQUIVALENT finding category not documented"
}

# ---------------------------------------------------------------------------
# 7. References output-format.md
# ---------------------------------------------------------------------------
@test "mutation-analyzer: references output-format.md" {
  grep -q "output-format.md" "$AGENT" \
    || fail "Agent does not reference output-format.md"
}
