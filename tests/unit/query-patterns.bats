#!/usr/bin/env bats
# Unit tests for shared/graph/query-patterns.md — the Cypher query reference.
# Note: query-patterns.md is created by a later task. Tests skip gracefully
# when the file does not yet exist so the suite does not fail prematurely.

load '../helpers/test-helpers'

QUERY_PATTERNS="$PLUGIN_ROOT/shared/graph/query-patterns.md"

# ---------------------------------------------------------------------------
# 1. query-patterns.md exists and is non-empty
# ---------------------------------------------------------------------------
@test "query-patterns.md exists and is non-empty" {
  if [[ ! -f "$QUERY_PATTERNS" ]]; then
    skip "shared/graph/query-patterns.md does not exist yet (created in a later task)"
  fi

  [[ -s "$QUERY_PATTERNS" ]] || fail "query-patterns.md exists but is empty"
}

# ---------------------------------------------------------------------------
# 2. All Cypher code blocks contain MATCH or CREATE
# ---------------------------------------------------------------------------
@test "all Cypher fenced blocks contain MATCH or CREATE" {
  if [[ ! -f "$QUERY_PATTERNS" ]]; then
    skip "shared/graph/query-patterns.md does not exist yet (created in a later task)"
  fi

  # Extract content of each ```cypher ... ``` block
  local cypher_blocks
  cypher_blocks="$(python3 - "$QUERY_PATTERNS" <<'PYEOF'
import sys, re

content = open(sys.argv[1]).read()
# Match fenced cypher blocks (case-insensitive fence label)
blocks = re.findall(r'```[Cc]ypher\s+(.*?)```', content, re.DOTALL)
for i, block in enumerate(blocks):
    print(f"BLOCK_START_{i}")
    print(block.strip())
    print(f"BLOCK_END_{i}")
PYEOF
)"

  # Count total blocks
  local block_count
  block_count="$(python3 - "$QUERY_PATTERNS" <<'PYEOF'
import sys, re
content = open(sys.argv[1]).read()
blocks = re.findall(r'```[Cc]ypher\s+.*?```', content, re.DOTALL)
print(len(blocks))
PYEOF
)"

  # Assert at least one Cypher block exists
  if [[ "$block_count" -eq 0 ]]; then
    fail "query-patterns.md contains no fenced Cypher code blocks"
  fi

  # Check each block has MATCH or CREATE
  local invalid_blocks=0
  local current_block=""
  local in_block=0

  while IFS= read -r line; do
    # Strip Windows \r if present (Python on Windows emits \r\n; bash keeps \r).
    line="${line%$'\r'}"
    if [[ "$line" =~ ^BLOCK_START_[0-9]+$ ]]; then
      in_block=1
      current_block=""
      continue
    fi
    if [[ "$line" =~ ^BLOCK_END_[0-9]+$ ]]; then
      in_block=0
      if ! printf '%s' "$current_block" | grep -qE '(MATCH|CREATE)'; then
        invalid_blocks=$(( invalid_blocks + 1 ))
        echo "WARNING: Cypher block missing MATCH or CREATE: $current_block" >&3
      fi
      current_block=""
      continue
    fi
    if [[ "$in_block" -eq 1 ]]; then
      current_block="${current_block}${line}"$'\n'
    fi
  done <<< "$cypher_blocks"

  if [[ "$invalid_blocks" -gt 0 ]]; then
    fail "$invalid_blocks Cypher block(s) do not contain MATCH or CREATE"
  fi

  # Report count for informational purposes
  echo "Found $block_count Cypher block(s), all contain MATCH or CREATE" >&3
}
