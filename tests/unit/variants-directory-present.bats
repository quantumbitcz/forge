#!/usr/bin/env bats
# Phase 08: asserts each new framework has a populated variants/ directory.

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../.."

@test "flask variants/ has at least 3 .md files" {
  local n
  n=$(find "$PLUGIN_ROOT/modules/frameworks/flask/variants" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 3 ]
}

@test "laravel variants/ has at least 5 .md files" {
  local n
  n=$(find "$PLUGIN_ROOT/modules/frameworks/laravel/variants" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 5 ]
}

@test "rails variants/ has at least 4 .md files" {
  local n
  n=$(find "$PLUGIN_ROOT/modules/frameworks/rails/variants" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 4 ]
}
