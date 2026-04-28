#!/usr/bin/env bats
# AC-POLISH-005: fg-101 stale-worktree detection.
load '../helpers/test-helpers'

F101="$PLUGIN_ROOT/agents/fg-101-worktree-manager.md"

@test "fg-101 references using-git-worktrees pattern" {
  run grep -F 'superpowers:using-git-worktrees' "$F101"
  assert_success
}

@test "fg-101 emits WORKTREE-STALE finding" {
  run grep -F 'WORKTREE-STALE' "$F101"
  assert_success
}

@test "fg-101 documents stale_after_days config key" {
  run grep -F 'worktree.stale_after_days' "$F101"
  assert_success
}

@test "fg-101 default stale_after_days is 30" {
  run grep -E 'default 30|stale_after_days.*30' "$F101"
  assert_success
}

@test "fg-101 stale_after_days range 1-365" {
  run grep -E '1-365|range \[1, 365\]|1 to 365' "$F101"
  assert_success
}

@test "fg-101 detection mechanism uses worktree mtime" {
  run grep -E 'mtime|modification time|ctime' "$F101"
  assert_success
}
