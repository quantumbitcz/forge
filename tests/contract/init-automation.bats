#!/usr/bin/env bash
setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FORGE_INIT="$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "init-auto: documents project-local plugin generation" {
  grep -q "project-tools\|Project-Local Plugin" "$FORGE_INIT"
}

@test "init-auto: generates plugin.json" {
  grep -q "plugin.json" "$FORGE_INIT"
}

@test "init-auto: generates commit-msg-guard hook" {
  grep -q "commit-msg-guard" "$FORGE_INIT"
}

@test "init-auto: generates branch-name-guard hook" {
  grep -q "branch-name-guard" "$FORGE_INIT"
}

@test "init-auto: generates wrapper skills" {
  grep -q "run-tests\|/build\|/lint" "$FORGE_INIT"
}

@test "init-auto: offers implementation tasks" {
  grep -q "Run /forge run to implement\|setup tasks\|Setup Tasks" "$FORGE_INIT"
}

@test "init-auto: respects existing hooks" {
  grep -q "commit_enforcement.*external\|existing.*hooks\|NOT.*external" "$FORGE_INIT"
}

@test "init-auto: generates commit-reviewer agent" {
  grep -q "commit-reviewer" "$FORGE_INIT"
}

@test "init-auto: ensures .forge/ is gitignored" {
  grep -q "gitignore.*\.forge\|\.forge.*gitignore" "$FORGE_INIT"
}
