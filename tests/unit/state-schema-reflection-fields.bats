#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/../.."
SCHEMA="${ROOT}/shared/state-schema.md"

@test "state-schema: implementer_reflection_cycles_total documented at run level" {
  run grep -E '^\|\s*`implementer_reflection_cycles_total`' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "state-schema: reflection_divergence_count documented at run level" {
  run grep -E '^\|\s*`reflection_divergence_count`' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "state-schema: tasks[*].implementer_reflection_cycles documented" {
  run grep -E 'tasks\[\*\]\.implementer_reflection_cycles' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "state-schema: tasks[*].reflection_verdicts documented" {
  run grep -E 'tasks\[\*\]\.reflection_verdicts' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "state-schema: explicit isolation from convergence counters" {
  run grep -iF 'does NOT feed into' "$SCHEMA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reflection"* ]] || [[ "$output" == *"implementer_reflection_cycles"* ]]
}

@test "state-schema: changelog entry for 1.8.0" {
  run grep -E '^### 1\.8\.0' "$SCHEMA"
  [ "$status" -eq 0 ]
}
