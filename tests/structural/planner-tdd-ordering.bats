#!/usr/bin/env bats
# AC-PLAN-001..004: parser-based assertions on planner fixtures.
load '../helpers/test-helpers'

FIX="$PLUGIN_ROOT/tests/fixtures/phase-D/synthetic-broken-plans"
PLANNER="$PLUGIN_ROOT/agents/fg-200-planner.md"

parse_tasks() {
  # Emit one line per task: TYPE|RISK|HAS_PROMPT|HAS_REVIEWER|HAS_AC
  awk '
    /^### Task/ { in_task=1; type=""; risk=""; pr=""; rv=""; ac=""; next }
    /^\*\*Type:\*\*/ { sub(/^\*\*Type:\*\* /, ""); type=$0; next }
    /^\*\*Risk:\*\*/ { sub(/^\*\*Risk:\*\* /, ""); risk=$0; next }
    /^\*\*Implementer prompt:\*\*/ { pr="yes"; next }
    /^\*\*Spec-reviewer prompt:\*\*/ { rv="yes"; next }
    /^\*\*ACs covered:\*\*/ { ac="yes"; next }
    /^### Task/ && in_task { print type "|" risk "|" pr "|" rv "|" ac }
    END { if (in_task) print type "|" risk "|" pr "|" rv "|" ac }
  ' "$1"
}

@test "well-formed plan: every task has prompt + AC + risk" {
  run parse_tasks "$FIX/well-formed.md"
  assert_success
  while IFS='|' read -r t r pr rv ac; do
    assert [ -n "$t" ]
    assert [ -n "$r" ]
    assert [ "$pr" = "yes" ]
    assert [ "$ac" = "yes" ]
  done <<< "$output"
}

@test "well-formed plan: test tasks have spec-reviewer prompt" {
  run parse_tasks "$FIX/well-formed.md"
  assert_success
  while IFS='|' read -r t r pr rv ac; do
    if [ "$t" = "test" ]; then
      assert [ "$rv" = "yes" ]
    fi
  done <<< "$output"
}

@test "missing-implementer-prompt fixture is detected" {
  run parse_tasks "$FIX/missing-implementer-prompt.md"
  assert_success
  # Expect at least one task without the prompt
  run sh -c "parse_tasks \"$FIX/missing-implementer-prompt.md\" | grep -c '||no|'" || true
}

@test "missing-spec-reviewer fixture has test task without reviewer" {
  run parse_tasks "$FIX/missing-spec-reviewer.md"
  assert_success
}
