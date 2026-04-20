#!/usr/bin/env bats

setup() {
  SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"
}

@test "MEDIUM + shaper alternatives >= 2 triggers" {
  run python3 "$SPEC" detect-ambiguity --requirement "add full text search across the indexed document corpus with ranking and pagination support today please" --confidence MEDIUM --shaper-alternatives 2 --shaper-delta 5 --plan-cache-sim 0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *'"triggered": true'* ]]
  [[ "$output" == *'"shaper_alternatives>=2"'* ]]
}

@test "MEDIUM + keyword 'either' triggers" {
  run python3 "$SPEC" detect-ambiguity --requirement "use either a REST endpoint family or a GraphQL schema for the new public API surface" --confidence MEDIUM --shaper-alternatives 0 --plan-cache-sim 0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *'"triggered": true'* ]]
  [[ "$output" == *'"keyword_hit"'* ]]
}

@test "MEDIUM + REST/GraphQL slash between nouns triggers" {
  run python3 "$SPEC" detect-ambiguity --requirement "integrate the new REST/GraphQL gateway with the existing auth service and downstream subscription consumers cleanly" --confidence MEDIUM --shaper-alternatives 0 --plan-cache-sim 0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *'"keyword_hit"'* ]]
}

@test "HIGH confidence does not trigger regardless of signals" {
  run python3 "$SPEC" detect-ambiguity --requirement "either add inline comments or attach standalone notes for every captured artifact in the audit trail" --confidence HIGH --shaper-alternatives 3 --shaper-delta 1 --plan-cache-sim 0.45
  [ "$status" -eq 0 ]
  [[ "$output" == *'"triggered": false'* ]]
}

@test "LOW confidence does not trigger" {
  run python3 "$SPEC" detect-ambiguity --requirement "either add inline comments or attach standalone notes for every captured artifact in the audit trail" --confidence LOW --shaper-alternatives 3 --shaper-delta 1 --plan-cache-sim 0.45
  [ "$status" -eq 0 ]
  [[ "$output" == *'"triggered": false'* ]]
}

@test "MEDIUM + plan-cache marginal (0.45) triggers" {
  run python3 "$SPEC" detect-ambiguity --requirement "refactor the users module so that profile loading paths are extracted into a smaller dedicated service today" --confidence MEDIUM --shaper-alternatives 0 --plan-cache-sim 0.45
  [ "$status" -eq 0 ]
  [[ "$output" == *'"marginal_cache_hit"'* ]]
}

@test "plan-cache >= 0.60 suppresses trigger" {
  run python3 "$SPEC" detect-ambiguity --requirement "either way works" --confidence MEDIUM --shaper-alternatives 0 --plan-cache-sim 0.72
  [ "$status" -eq 0 ]
  [[ "$output" == *'"triggered": false'* ]]
}

@test "requirement under 15 words suppresses trigger" {
  run python3 "$SPEC" detect-ambiguity --requirement "add auth" --confidence MEDIUM --shaper-alternatives 2 --shaper-delta 2 --plan-cache-sim 0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *'"triggered": false'* ]]
  [[ "$output" == *'requirement_too_short'* ]]
}

@test "shaper override: trigger_reason[0] is shaper_alternatives>=2 when shaper fires" {
  run python3 "$SPEC" detect-ambiguity --requirement "consider either a REST or a GraphQL flavored API design with paged responses for the new service surface" --confidence MEDIUM --shaper-alternatives 2 --shaper-delta 3 --plan-cache-sim 0.45
  [ "$status" -eq 0 ]
  [[ "$output" == *'"reasons": ["shaper_alternatives>=2"'* ]]
}

@test "OR semantics: keyword alone with no shaper triggers" {
  run python3 "$SPEC" detect-ambiguity --requirement "we could consider multiple approaches for storing user preferences data including encrypted blobs and structured rows" --confidence MEDIUM --shaper-alternatives 0 --plan-cache-sim 0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *'"triggered": true'* ]]
  [[ "$output" == *'"keyword_hit"'* ]]
  [[ "$output" != *'"shaper_alternatives>=2"'* ]]
}
