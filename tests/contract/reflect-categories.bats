#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/../.."
REGISTRY="${ROOT}/shared/checks/category-registry.json"

@test "reflect-categories: REFLECT wildcard present" {
  run jq -e '.categories.REFLECT' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: REFLECT owned by fg-301" {
  run jq -r '.categories.REFLECT.agents[]' "$REGISTRY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fg-301-implementer-critic"* ]]
}

@test "reflect-categories: REFLECT is wildcard" {
  run jq -r '.categories.REFLECT.wildcard' "$REGISTRY"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "reflect-categories: REFLECT-DIVERGENCE discrete entry" {
  run jq -e '.categories["REFLECT-DIVERGENCE"]' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: REFLECT-HARDCODED-RETURN discrete entry" {
  run jq -e '.categories["REFLECT-HARDCODED-RETURN"]' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: REFLECT-OVER-NARROW discrete entry" {
  run jq -e '.categories["REFLECT-OVER-NARROW"]' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: REFLECT-MISSING-BRANCH discrete entry" {
  run jq -e '.categories["REFLECT-MISSING-BRANCH"]' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: scoring.md mentions REFLECT-* wildcard" {
  run grep -E 'REFLECT-\*' "${ROOT}/shared/scoring.md"
  [ "$status" -eq 0 ]
}
