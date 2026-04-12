#!/usr/bin/env bats
# Contract test: graph-debug skill structure and safety.

load '../helpers/test-helpers'

SKILL_FILE="$PLUGIN_ROOT/skills/graph-debug/SKILL.md"

@test "graph-debug: skill file exists" {
  [[ -f "$SKILL_FILE" ]]
}

@test "graph-debug: has valid frontmatter with name and description" {
  # Extract frontmatter
  local frontmatter
  frontmatter="$(awk '/^---$/{n++; if(n==2) exit; next} n==1{print}' "$SKILL_FILE")"
  echo "$frontmatter" | grep -q "^name: graph-debug" || fail "Missing name: graph-debug"
  echo "$frontmatter" | grep -q "^description:" || fail "Missing description field"
}

@test "graph-debug: all Cypher queries are read-only" {
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
