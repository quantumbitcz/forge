#!/usr/bin/env bats
# Contract tests: every framework's forge-config-template.md carries the
# Phase 6 cost-governance `cost:` block.
#
# Note on regex vs fenced blocks: grep operates on raw text and does NOT respect
# triple-backtick fence context — a `ceiling_usd: 25.00` literal anywhere in the
# file (including inside an example fenced YAML block) satisfies the assertion.
# This is intentional and matches existing contract-test precedent: presence of
# the literal is what we're proving.

load '../helpers/test-helpers'

@test "every framework template declares cost.ceiling_usd" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-config-template.md; do
    run grep -E "^\s*ceiling_usd:\s*25\.00" "$tpl"
    assert_success "missing cost.ceiling_usd in $tpl"
  done
}

@test "every framework template declares cost.aware_routing" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-config-template.md; do
    run grep -E "^\s*aware_routing:\s*true" "$tpl"
    assert_success "missing cost.aware_routing in $tpl"
  done
}

@test "every framework template declares tier_estimates_usd.premium = 0.078" {
  for tpl in $PLUGIN_ROOT/modules/frameworks/*/forge-config-template.md; do
    run grep -E "premium:\s*0\.078" "$tpl"
    assert_success "missing premium tier estimate in $tpl"
  done
}
