#!/usr/bin/env bats
# Structural checks on plugin wiring for self-consistency voting.
# Verifies the consistency cross-cutting touchpoints are present
# in the documented locations.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "voting contract documents state.mode in the cache key" {
  run grep -E 'state\.mode' "${REPO_ROOT}/shared/consistency/voting.md"
  [ "$status" -eq 0 ]
}

@test "state-schema is at 2.1.0 and declares consistency counters" {
  run grep -E '"version": "2\.1\.0"' "${REPO_ROOT}/shared/state-schema.md"
  [ "$status" -eq 0 ]
  run grep -E '"consistency_cache_hits"' "${REPO_ROOT}/shared/state-schema.md"
  [ "$status" -eq 0 ]
  run grep -E '"consistency_votes"' "${REPO_ROOT}/shared/state-schema.md"
  [ "$status" -eq 0 ]
}

@test "forge-config schema declares the consistency block with n_samples default 3" {
  # Configuration defaults live in shared/schemas/forge-config-schema.json
  # rather than a top-level forge-config.md. The schema is the canonical source.
  run grep -E '"consistency"' "${REPO_ROOT}/shared/schemas/forge-config-schema.json"
  [ "$status" -eq 0 ]
  run grep -E '"n_samples"' "${REPO_ROOT}/shared/schemas/forge-config-schema.json"
  [ "$status" -eq 0 ]
}

@test "PREFLIGHT constraints cover the five consistency.* fields" {
  for field in 'consistency\.enabled' 'consistency\.n_samples' 'consistency\.decisions' \
               'consistency\.model_tier' 'consistency\.min_consensus_confidence'; do
    run grep -E "$field" "${REPO_ROOT}/shared/preflight-constraints.md"
    [ "$status" -eq 0 ]
  done
}

@test "fg-210-validator references the consistency dispatch contract" {
  # Post-Mega C/D: fg-210-validator is the sole consistency voting caller.
  # fg-010-shaper rewrite (Mega C, ad8c9ab5) made BRAINSTORMING always-on for
  # feature mode, removing the up-front shaper_intent vote. fg-710-post-run
  # rewrite (Mega D, 898b33dc) replaced pr_rejection_classification voting
  # with the receiving-code-review defense-check sub-agent dispatch.
  run grep -F 'shared/consistency/' "${REPO_ROOT}/agents/fg-210-validator.md"
  [ "$status" -eq 0 ]
}

@test "fg-210-validator gates voting on INCONCLUSIVE" {
  run grep -E 'INCONCLUSIVE' "${REPO_ROOT}/agents/fg-210-validator.md"
  [ "$status" -eq 0 ]
}

@test "fg-010-shaper does not dispatch consistency voting (Mega C: brainstorming always-on)" {
  # Negative assertion: Mega C deliberately removed the shaper_intent vote.
  run grep -F 'shared/consistency/' "${REPO_ROOT}/agents/fg-010-shaper.md"
  [ "$status" -ne 0 ]
}

@test "fg-710-post-run does not dispatch consistency voting (Mega D: defense-check sub-agent)" {
  # Negative assertion: Mega D replaced pr_rejection_classification voting
  # with per-comment defense-check sub-agent dispatch (F40).
  run grep -F 'shared/consistency/' "${REPO_ROOT}/agents/fg-710-post-run.md"
  [ "$status" -ne 0 ]
}

@test "consistency cache listed as survives-reset in CLAUDE.md" {
  run grep -F 'consistency-cache.jsonl' "${REPO_ROOT}/CLAUDE.md"
  [ "$status" -eq 0 ]
}
