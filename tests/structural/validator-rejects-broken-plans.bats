#!/usr/bin/env bats
# AC-PLAN-005..009: synthetic-fixture assertions on broken plans.
#
# These tests verify that the synthetic broken-plan fixtures under
# tests/fixtures/phase-D/synthetic-broken-plans/ exercise the contract
# violations that fg-210-validator must reject (W1..W5). The tests parse
# fixtures directly — they do not invoke the validator. The validator
# itself is contract-tested in tests/structural/planner-tdd-ordering.bats
# and the matching contract tests under tests/contract/.
load '../helpers/test-helpers'

FIX="$PLUGIN_ROOT/tests/fixtures/phase-D/synthetic-broken-plans"
VALIDATOR="$PLUGIN_ROOT/agents/fg-210-validator.md"

# parse_tasks <plan-file>
# Emit one line per ### Task block: TYPE|RISK|HAS_PROMPT|HAS_REVIEWER|HAS_AC.
# Implemented as a single awk that flushes on every ### Task boundary AND in END.
parse_tasks() {
  awk '
    function flush() {
      if (in_task) {
        print type "|" risk "|" pr "|" rv "|" ac
      }
    }
    /^### Task/ {
      flush()
      in_task=1; type=""; risk=""; pr="no"; rv="no"; ac="no"
      next
    }
    /^\*\*Type:\*\*/        { sub(/^\*\*Type:\*\*[[:space:]]*/, ""); type=$0; next }
    /^\*\*Risk:\*\*/        { sub(/^\*\*Risk:\*\*[[:space:]]*/, ""); risk=$0; next }
    /^\*\*Implementer prompt:\*\*/   { pr="yes"; next }
    /^\*\*Spec-reviewer prompt:\*\*/ { rv="yes"; next }
    /^\*\*ACs covered:\*\*/          { ac="yes"; next }
    END { flush() }
  ' "$1"
}

@test "fixture directory exists with expected broken plans" {
  assert [ -d "$FIX" ]
  for f in well-formed.md missing-implementer-prompt.md missing-spec-reviewer.md missing-test-task.md missing-risk-justification.md short-risk-justification.md; do
    assert [ -f "$FIX/$f" ]
  done
}

@test "well-formed fixture: every task has a non-empty Type, Risk, prompt, AC" {
  run parse_tasks "$FIX/well-formed.md"
  assert_success
  while IFS='|' read -r t r pr rv ac; do
    [ -z "$t" ] && continue
    assert [ -n "$t" ]
    assert [ -n "$r" ]
    assert [ "$pr" = "yes" ]
    assert [ "$ac" = "yes" ]
  done <<< "$output"
}

@test "well-formed fixture: every test task has a spec-reviewer prompt" {
  run parse_tasks "$FIX/well-formed.md"
  assert_success
  while IFS='|' read -r t r pr rv ac; do
    [ -z "$t" ] && continue
    if [ "$t" = "test" ]; then
      assert [ "$rv" = "yes" ]
    fi
  done <<< "$output"
}

@test "missing-implementer-prompt fixture: at least one task has pr=no" {
  output="$(parse_tasks "$FIX/missing-implementer-prompt.md")"
  count="$(awk -F'|' '$3 == "no" { c++ } END { print c+0 }' <<< "$output")"
  assert [ "$count" -ge 1 ]
}

@test "missing-spec-reviewer fixture: at least one test task has rv=no" {
  output="$(parse_tasks "$FIX/missing-spec-reviewer.md")"
  count="$(awk -F'|' '$1 == "test" && $4 == "no" { c++ } END { print c+0 }' <<< "$output")"
  assert [ "$count" -ge 1 ]
}

@test "missing-test-task fixture: implementation tasks outnumber test tasks" {
  output="$(parse_tasks "$FIX/missing-test-task.md")"
  impl_count="$(awk -F'|' '$1 == "implementation" { c++ } END { print c+0 }' <<< "$output")"
  test_count="$(awk -F'|' '$1 == "test" { c++ } END { print c+0 }' <<< "$output")"
  assert [ "$impl_count" -gt "$test_count" ]
}

@test "validator declares all five W rules (W1..W5)" {
  for rule in 'Rule W1' 'Rule W2' 'Rule W3' 'Rule W4' 'Rule W5'; do
    run grep -F "$rule" "$VALIDATOR"
    assert_success
  done
}
