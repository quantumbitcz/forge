#!/usr/bin/env bats
# AC-2 / AC-3: install helpers exist at repo root.
load '../helpers/test-helpers'

@test "install.sh exists at repo root" {
  assert [ -f "$PLUGIN_ROOT/install.sh" ]
}

@test "install.sh is executable" {
  assert [ -x "$PLUGIN_ROOT/install.sh" ]
}

@test "install.sh has bash shebang" {
  run head -1 "$PLUGIN_ROOT/install.sh"
  assert_output --regexp '^#!/usr/bin/env bash'
}

@test "install.sh supports --help" {
  run bash "$PLUGIN_ROOT/install.sh" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "install.sh supports --dry-run" {
  run bash "$PLUGIN_ROOT/install.sh" --dry-run
  assert_success
  assert_output --partial "dry-run"
}

@test "install.ps1 exists at repo root" {
  assert [ -f "$PLUGIN_ROOT/install.ps1" ]
}

@test "install.ps1 has a param block" {
  run grep -E '^\s*param\s*\(' "$PLUGIN_ROOT/install.ps1"
  assert_success
}

@test "install.ps1 supports -Help" {
  run grep -E '\[switch\]\s*\$Help' "$PLUGIN_ROOT/install.ps1"
  assert_success
}

@test "install.ps1 supports -WhatIf" {
  run grep -E '\[switch\]\s*\$WhatIf' "$PLUGIN_ROOT/install.ps1"
  assert_success
}
