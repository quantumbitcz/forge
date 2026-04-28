#!/usr/bin/env bats
# Contract tests: every framework's forge-config-template.md carries the
# Phase 7 `intent_verification:` and `impl_voting:` blocks introduced in
# Task 4 of docs/superpowers/plans/2026-04-22-phase-7-intent-assurance.md.
#
# Note: grep operates on raw text and does NOT respect triple-backtick fence
# context — presence of the literal anywhere in the file satisfies the
# assertion. Matches existing contract-test precedent (see
# framework-config-templates.bats).

load '../helpers/test-helpers'

@test "every framework template declares intent_verification block" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-admin config-template.md; do
    run grep -E "^intent_verification:" "$tpl"
    assert_success "missing intent_verification: in $tpl"
  done
}

@test "every framework template declares impl_voting block" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-admin config-template.md; do
    run grep -E "^impl_voting:" "$tpl"
    assert_success "missing impl_voting: in $tpl"
  done
}

@test "every framework template sets impl_voting.samples to 2" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-admin config-template.md; do
    run grep -E "^\s*samples:\s*2" "$tpl"
    assert_success "missing samples: 2 in $tpl"
  done
}

@test "every framework template sets impl_voting.skip_if_budget_remaining_below_pct to 30" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-admin config-template.md; do
    run grep -E "^\s*skip_if_budget_remaining_below_pct:\s*30" "$tpl"
    assert_success "missing skip_if_budget_remaining_below_pct: 30 in $tpl"
  done
}
