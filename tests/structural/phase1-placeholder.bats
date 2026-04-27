#!/usr/bin/env bats
# Phase 1 sentinel — deleted in the final task.
load '../helpers/test-helpers'

@test "phase-1 branch is live" {
  assert [ -f "$PLUGIN_ROOT/CLAUDE.md" ]
}
