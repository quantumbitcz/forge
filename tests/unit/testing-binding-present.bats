#!/usr/bin/env bats
# Asserts each new framework has a testing/ binding file.

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../.."

@test "flask testing/pytest.md exists" {
  [ -f "$PLUGIN_ROOT/modules/frameworks/flask/testing/pytest.md" ]
}

@test "laravel testing/phpunit.md exists" {
  [ -f "$PLUGIN_ROOT/modules/frameworks/laravel/testing/phpunit.md" ]
}

@test "rails testing/rspec.md exists" {
  [ -f "$PLUGIN_ROOT/modules/frameworks/rails/testing/rspec.md" ]
}

@test "flask testing binding references generic pytest module" {
  grep -q 'modules/testing/pytest.md' "$PLUGIN_ROOT/modules/frameworks/flask/testing/pytest.md"
}

@test "laravel testing binding references generic phpunit module" {
  grep -q 'modules/testing/phpunit.md' "$PLUGIN_ROOT/modules/frameworks/laravel/testing/phpunit.md"
}

@test "rails testing binding references generic rspec module" {
  grep -q 'modules/testing/rspec.md' "$PLUGIN_ROOT/modules/frameworks/rails/testing/rspec.md"
}
