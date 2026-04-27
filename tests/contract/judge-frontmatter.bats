#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "fg-205-plan-judge frontmatter has ui.tasks=false ui.ask=false" {
  AGENT="$PROJECT_ROOT/agents/fg-205-plan-judge.md"
  run grep -E '^  tasks: false$' "$AGENT"
  [ "$status" -eq 0 ]
  run grep -E '^  ask: false$' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "fg-301-implementer-judge frontmatter declares model: fast" {
  AGENT="$PROJECT_ROOT/agents/fg-301-implementer-judge.md"
  run grep -E '^model: fast$' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "fg-301-implementer-judge tools: [Read]" {
  AGENT="$PROJECT_ROOT/agents/fg-301-implementer-judge.md"
  run grep -E "^tools: \\['Read'\\]$" "$AGENT"
  [ "$status" -eq 0 ]
}

@test "fg-205-plan-judge body declares binding veto" {
  AGENT="$PROJECT_ROOT/agents/fg-205-plan-judge.md"
  run grep -iF 'binding' "$AGENT"
  [ "$status" -eq 0 ]
  run grep -iF 'veto' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "fg-301-implementer-judge body declares binding veto" {
  AGENT="$PROJECT_ROOT/agents/fg-301-implementer-judge.md"
  run grep -iF 'binding' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "judges declare 2-loop bound" {
  for AGENT in "$PROJECT_ROOT/agents/fg-205-plan-judge.md" "$PROJECT_ROOT/agents/fg-301-implementer-judge.md"; do
    run grep -F '2 loops' "$AGENT"
    [ "$status" -eq 0 ] || {
      run grep -F '2-loop' "$AGENT"
      [ "$status" -eq 0 ]
    }
  done
}
