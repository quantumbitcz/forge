#!/usr/bin/env bats
#
# AC4: fg-100-orchestrator.md documents the Relevant Learnings injection
# at the planner, implementer, quality-gate and reviewer dispatch sites.

setup() {
  DOC="$BATS_TEST_DIRNAME/../../agents/fg-100-orchestrator.md"
}

@test "§0.6.1 Dispatch-Context Builder exists" {
  run grep -F "§0.6.1 Dispatch-Context Builder" "$DOC"
  [ "$status" -eq 0 ]
}

@test "builder references learnings_selector + format + markers + role_map" {
  run grep -F "learnings_selector.select_for_dispatch" "$DOC"
  [ "$status" -eq 0 ]
  run grep -F "learnings_format.render" "$DOC"
  [ "$status" -eq 0 ]
  run grep -F "learnings_markers.parse_markers" "$DOC"
  [ "$status" -eq 0 ]
  run grep -F "agent_role_map.role_for_agent" "$DOC"
  [ "$status" -eq 0 ]
}

@test "planner dispatch mentions Relevant Learnings auto-append" {
  run awk '/SS2\.2 Standard Planning/{flag=1} flag; /SS2\.3/{exit}' "$DOC"
  echo "$output" | grep -qF "## Relevant Learnings"
}

@test "implementer dispatch mentions Relevant Learnings auto-append" {
  run grep -B2 -A4 "\[dispatch fg-300-implementer\]" "$DOC"
  echo "$output" | grep -qF "## Relevant Learnings"
}

@test "quality gate and reviewer blocks present in §0.6.1" {
  run grep -F "fg-410 .. fg-419" "$DOC"
  [ "$status" -eq 0 ]
  run grep -F "fg-400-quality-gate" "$DOC"
  [ "$status" -eq 0 ]
}
