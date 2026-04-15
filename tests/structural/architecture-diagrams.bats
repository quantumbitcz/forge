#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "pipeline-flow.md exists and contains mermaid" {
  local f="${PLUGIN_ROOT}/docs/architecture/pipeline-flow.md"
  assert [ -f "$f" ]
  run grep -c 'mermaid' "$f"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "agent-dispatch.md exists and contains mermaid" {
  local f="${PLUGIN_ROOT}/docs/architecture/agent-dispatch.md"
  assert [ -f "$f" ]
  run grep -c 'mermaid' "$f"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "state-machine.md exists and contains mermaid" {
  local f="${PLUGIN_ROOT}/docs/architecture/state-machine.md"
  assert [ -f "$f" ]
  run grep -c 'mermaid' "$f"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "no references to deleted skill-routing-guide.md" {
  local count
  count=$(grep -rl 'skill-routing-guide' "${PLUGIN_ROOT}"/ --include='*.md' 2>/dev/null | grep -v 'docs/superpowers/' | grep -v 'CHANGELOG.md' | wc -l | tr -d ' ')
  assert [ "$count" -eq 0 ]
}
