#!/usr/bin/env bats
# Contract tests: infra-deploy-verifier supports Tiers 4-5.

load '../helpers/test-helpers'

VERIFIER="$PLUGIN_ROOT/agents/infra-deploy-verifier.md"

@test "infra-tiers: verifier documents Tier 4 contract testing" {
  grep -qi 'tier 4' "$VERIFIER"
  grep -qi 'contract' "$VERIFIER"
  grep -qi 'stub' "$VERIFIER"
}

@test "infra-tiers: verifier documents Tier 5 full stack integration" {
  grep -qi 'tier 5' "$VERIFIER"
  grep -qi 'full stack\|integration' "$VERIFIER"
  grep -qi 'image_source\|registry\|build' "$VERIFIER"
}

@test "infra-tiers: verifier supports max_verification_tier up to 5" {
  grep -q 'max_verification_tier' "$VERIFIER"
}

@test "infra-tiers: verifier documents health/smoke/scenario test layers" {
  grep -qi 'health' "$VERIFIER"
  grep -qi 'smoke' "$VERIFIER"
  grep -qi 'scenario\|tests/infra/' "$VERIFIER"
}

@test "infra-tiers: verifier documents image resolution modes" {
  grep -qi 'registry' "$VERIFIER"
  grep -qi 'build' "$VERIFIER"
  grep -qi 'auto' "$VERIFIER"
}

@test "infra-tiers: scoring.md includes INFRA-HEALTH code" {
  grep -q 'INFRA-HEALTH' "$PLUGIN_ROOT/shared/scoring.md"
}

@test "infra-tiers: scoring.md includes INFRA-CONTRACT code" {
  grep -q 'INFRA-CONTRACT' "$PLUGIN_ROOT/shared/scoring.md"
}

@test "infra-tiers: scoring.md includes INFRA-E2E code" {
  grep -q 'INFRA-E2E' "$PLUGIN_ROOT/shared/scoring.md"
}

@test "infra-tiers: scoring.md includes INFRA-IMAGE code" {
  grep -q 'INFRA-IMAGE' "$PLUGIN_ROOT/shared/scoring.md"
}

@test "infra-tiers: k8s conventions document tests/infra/" {
  grep -q 'tests/infra/' "$PLUGIN_ROOT/modules/frameworks/k8s/conventions.md"
}
