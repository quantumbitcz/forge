#!/usr/bin/env bats
# Contract test: forge-graph-debug skill structure and safety.

load '../helpers/test-helpers'

SKILL_FILE="$PLUGIN_ROOT/skills/forge-graph-debug/SKILL.md"

@test "forge-graph-debug: skill file exists" {
  [[ -f "$SKILL_FILE" ]]
}

@test "forge-graph-debug: has valid frontmatter with name and description" {
  # get_frontmatter() provided by test-helpers.bash
  local frontmatter
  frontmatter="$(get_frontmatter "$SKILL_FILE")"
  echo "$frontmatter" | grep -q "^name: forge-graph-debug" || fail "Missing name: forge-graph-debug"
  echo "$frontmatter" | grep -q "^description:" || fail "Missing description field"
}

@test "forge-graph-debug: all Cypher queries have LIMIT clause" {
  # Safety section claims "All queries enforce LIMIT"
  local missing=0
  local block=""
  local in_block=0
  while IFS= read -r line; do
    if [[ "$line" =~ \`\`\`cypher ]]; then
      in_block=1; block=""; continue
    fi
    if [[ "$line" =~ \`\`\` ]] && (( in_block )); then
      if ! echo "$block" | grep -qi "LIMIT"; then
        missing=$((missing + 1))
      fi
      in_block=0; continue
    fi
    (( in_block )) && block="${block}${line}\n"
  done < "$SKILL_FILE"
  [[ "$missing" -eq 0 ]] || fail "$missing Cypher blocks missing LIMIT clause"
}

@test "forge-graph-debug: all Cypher queries are read-only" {
  # No CREATE, MERGE, DELETE, SET, DETACH, REMOVE in Cypher blocks
  local violations=()
  while IFS= read -r line; do
    if echo "$line" | grep -qiE "^\s*(CREATE|MERGE|DELETE|DETACH|SET|REMOVE)\b"; then
      violations+=("$line")
    fi
  done < <(awk '/```cypher/,/```/' "$SKILL_FILE" | grep -v '```')

  if (( ${#violations[@]} > 0 )); then
    printf 'Write operation: %s\n' "${violations[@]}"
    fail "Graph-debug skill contains write operations: ${#violations[@]}"
  fi
}
