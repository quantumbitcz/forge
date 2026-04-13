#!/usr/bin/env bats
# Contract tests: fg-135-wiki-generator agent compliance.

load '../helpers/test-helpers'

AGENT_FILE="$PLUGIN_ROOT/agents/fg-135-wiki-generator.md"

# ---------------------------------------------------------------------------
# 1. File existence
# ---------------------------------------------------------------------------
@test "wiki-generator: agents/fg-135-wiki-generator.md exists" {
  [ -f "$AGENT_FILE" ] || fail "agents/fg-135-wiki-generator.md not found"
}

# ---------------------------------------------------------------------------
# 2. Correct name in frontmatter
# ---------------------------------------------------------------------------
@test "wiki-generator: name field is fg-135-wiki-generator" {
  local name_value
  name_value="$(get_frontmatter "$AGENT_FILE" | grep '^name:' | sed 's/^name:[[:space:]]*//')"
  [ "$name_value" = "fg-135-wiki-generator" ] \
    || fail "Expected name 'fg-135-wiki-generator', got '$name_value'"
}

# ---------------------------------------------------------------------------
# 3. Description present
# ---------------------------------------------------------------------------
@test "wiki-generator: has description field" {
  get_frontmatter "$AGENT_FILE" | grep -q '^description:' \
    || fail "Missing description: field in frontmatter"
}

# ---------------------------------------------------------------------------
# 4. Tools include LSP
# ---------------------------------------------------------------------------
@test "wiki-generator: tools include LSP" {
  get_frontmatter "$AGENT_FILE" | grep -q 'LSP' \
    || fail "LSP not listed in tools"
}

# ---------------------------------------------------------------------------
# 5. Documents wiki structure
# ---------------------------------------------------------------------------
@test "wiki-generator: documents wiki structure" {
  grep -q "index.md" "$AGENT_FILE" \
    || fail "Wiki structure does not mention index.md"
  grep -q "architecture.md" "$AGENT_FILE" \
    || fail "Wiki structure does not mention architecture.md"
  grep -q "api-surface.md" "$AGENT_FILE" \
    || fail "Wiki structure does not mention api-surface.md"
  grep -q "data-model.md" "$AGENT_FILE" \
    || fail "Wiki structure does not mention data-model.md"
  grep -q "conventions-summary.md" "$AGENT_FILE" \
    || fail "Wiki structure does not mention conventions-summary.md"
  grep -q "dependency-graph.md" "$AGENT_FILE" \
    || fail "Wiki structure does not mention dependency-graph.md"
}

# ---------------------------------------------------------------------------
# 6. Documents .wiki-meta.json
# ---------------------------------------------------------------------------
@test "wiki-generator: documents .wiki-meta.json" {
  grep -q ".wiki-meta.json" "$AGENT_FILE" \
    || fail ".wiki-meta.json not documented"
}

@test "wiki-generator: documents last_sha field in wiki-meta" {
  grep -q "last_sha" "$AGENT_FILE" \
    || fail "last_sha field not documented"
}

@test "wiki-generator: documents schema_version field in wiki-meta" {
  grep -q "schema_version" "$AGENT_FILE" \
    || fail "schema_version field not documented"
}

@test "wiki-generator: documents generated_at field in wiki-meta" {
  grep -q "generated_at" "$AGENT_FILE" \
    || fail "generated_at field not documented"
}

@test "wiki-generator: documents file_count field in wiki-meta" {
  grep -q "file_count" "$AGENT_FILE" \
    || fail "file_count field not documented"
}

# ---------------------------------------------------------------------------
# 7. Documents configuration
# ---------------------------------------------------------------------------
@test "wiki-generator: documents wiki.enabled configuration" {
  grep -q "wiki.enabled" "$AGENT_FILE" \
    || fail "wiki.enabled configuration not documented"
}

@test "wiki-generator: documents wiki.auto_update configuration" {
  grep -q "wiki.auto_update\|auto_update" "$AGENT_FILE" \
    || fail "wiki.auto_update configuration not documented"
}

@test "wiki-generator: documents wiki.include_api_surface configuration" {
  grep -q "include_api_surface" "$AGENT_FILE" \
    || fail "wiki.include_api_surface configuration not documented"
}

@test "wiki-generator: documents wiki.include_data_model configuration" {
  grep -q "include_data_model" "$AGENT_FILE" \
    || fail "wiki.include_data_model configuration not documented"
}

@test "wiki-generator: documents wiki.max_module_depth configuration" {
  grep -q "max_module_depth" "$AGENT_FILE" \
    || fail "wiki.max_module_depth configuration not documented"
}

# ---------------------------------------------------------------------------
# 8. Documents generation modes
# ---------------------------------------------------------------------------
@test "wiki-generator: documents full generation mode" {
  grep -qi "full generation\|Full Generation" "$AGENT_FILE" \
    || fail "Full generation mode not documented"
}

@test "wiki-generator: documents incremental generation mode" {
  grep -qi "incremental generation\|Incremental Generation" "$AGENT_FILE" \
    || fail "Incremental generation mode not documented"
}

# ---------------------------------------------------------------------------
# 9. Documents forbidden actions
# ---------------------------------------------------------------------------
@test "wiki-generator: documents forbidden actions" {
  grep -qi "forbidden\|Forbidden" "$AGENT_FILE" \
    || fail "Forbidden actions section not documented"
}

@test "wiki-generator: forbids modifying source code" {
  grep -qi "DO NOT modify source code\|do not modify source" "$AGENT_FILE" \
    || fail "Source code modification prohibition not documented"
}

@test "wiki-generator: forbids creating files outside .forge/wiki" {
  grep -qi "outside.*\.forge/wiki\|DO NOT create files outside" "$AGENT_FILE" \
    || fail "File creation restriction not documented"
}
