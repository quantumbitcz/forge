#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "no agent file is named *-critic.md" {
  run bash -c "cd '$PROJECT_ROOT/agents' && ls | grep -E 'critic\\.md$' || true"
  [ -z "$output" ]
}

@test "fg-205-plan-judge.md exists with matching frontmatter name" {
  AGENT="$PROJECT_ROOT/agents/fg-205-plan-judge.md"
  [ -f "$AGENT" ]
  run grep -E '^name: fg-205-plan-judge$' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "fg-301-implementer-judge.md exists with matching frontmatter name" {
  AGENT="$PROJECT_ROOT/agents/fg-301-implementer-judge.md"
  [ -f "$AGENT" ]
  run grep -E '^name: fg-301-implementer-judge$' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "shared/agents.md registry references fg-205-plan-judge" {
  run grep -F 'fg-205-plan-judge' "$PROJECT_ROOT/shared/agents.md"
  [ "$status" -eq 0 ]
}

@test "shared/agents.md registry references fg-301-implementer-judge" {
  run grep -F 'fg-301-implementer-judge' "$PROJECT_ROOT/shared/agents.md"
  [ "$status" -eq 0 ]
}
