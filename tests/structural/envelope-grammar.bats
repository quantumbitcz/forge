#!/usr/bin/env bats
# Structural validity of shared/untrusted-envelope.md.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DOC="$ROOT/shared/untrusted-envelope.md"
}

@test "untrusted-envelope.md exists" {
  [ -f "$DOC" ]
}

@test "doc contains ABNF section" {
  grep -q "^## ABNF Grammar" "$DOC"
}

@test "doc contains tier mapping table" {
  grep -q "^## Tier Mapping" "$DOC"
}

@test "tier table contains all known sources" {
  for src in "mcp:linear" "mcp:slack" "mcp:figma" "mcp:github" "mcp:playwright" "mcp:context7" "wiki" "explore-cache" "plan-cache" "docs-discovery" "cross-project-learnings" "neo4j:project" "webfetch" "deprecation-refresh"; do
    grep -qF "| \`$src\`" "$DOC" || { echo "missing source: $src"; return 1; }
  done
}

@test "doc standardizes on bytes for size limits" {
  grep -qE "max_envelope_bytes.*65536" "$DOC"
  grep -qE "max_aggregate_bytes.*262144" "$DOC"
}

@test "doc references preflight-constraints.md" {
  grep -q "shared/preflight-constraints.md" "$DOC"
}
