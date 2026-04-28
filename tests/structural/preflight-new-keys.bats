#!/usr/bin/env bats
# Asserts that shared/preflight-constraints.md documents all new config keys
# from the mega-consolidation spec §11.1.
#
# Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §11.1.
# AC:   AC-S028.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    CONSTRAINTS="$REPO_ROOT/shared/preflight-constraints.md"
}

@test "BRAINSTORMING keys are documented" {
    grep -F "brainstorm.enabled" "$CONSTRAINTS"
    grep -F "brainstorm.spec_dir" "$CONSTRAINTS"
    grep -F "brainstorm.autonomous_extractor_min_confidence" "$CONSTRAINTS"
    grep -F "brainstorm.transcript_mining.enabled" "$CONSTRAINTS"
    grep -F "brainstorm.transcript_mining.top_k" "$CONSTRAINTS"
    grep -F "brainstorm.transcript_mining.max_chars" "$CONSTRAINTS"
}

@test "consistency-promotion keys are documented" {
    grep -F "quality_gate.consistency_promotion.enabled" "$CONSTRAINTS"
    grep -F "quality_gate.consistency_promotion.threshold" "$CONSTRAINTS"
}

@test "bug investigator keys are documented" {
    grep -F "bug.hypothesis_branching.enabled" "$CONSTRAINTS"
    grep -F "bug.fix_gate_threshold" "$CONSTRAINTS"
}

@test "post_run defense keys are documented" {
    grep -F "post_run.defense_enabled" "$CONSTRAINTS"
    grep -F "post_run.defense_min_evidence" "$CONSTRAINTS"
}

@test "pr_builder keys are documented" {
    grep -F "pr_builder.default_strategy" "$CONSTRAINTS"
    grep -F "pr_builder.cleanup_checklist_enabled" "$CONSTRAINTS"
}

@test "worktree.stale_after_days is documented" {
    grep -F "worktree.stale_after_days" "$CONSTRAINTS"
}

@test "platform.detection and platform.remote_name are documented" {
    grep -F "platform.detection" "$CONSTRAINTS"
    grep -F "platform.remote_name" "$CONSTRAINTS"
}

@test "pr_builder.default_strategy enum lists open-pr-draft as default" {
    # Spec §11.1: default is open-pr-draft.
    grep -E "pr_builder.default_strategy.*open-pr-draft" "$CONSTRAINTS"
}

@test "platform.detection enum is exactly auto|github|gitlab|bitbucket|gitea" {
    grep -E "platform.detection.*auto.*github.*gitlab.*bitbucket.*gitea" "$CONSTRAINTS"
}

@test "brainstorm.spec_dir documents the PREFLIGHT write-probe (AC-S028)" {
    # Spec §11.1: parent directory of brainstorm.spec_dir must exist or be creatable;
    # PREFLIGHT runs a write probe.
    grep -E "brainstorm.spec_dir.*write probe|write probe.*PREFLIGHT" "$CONSTRAINTS"
}

@test "brainstorm.autonomous_extractor_min_confidence enum lists low|medium|high" {
    grep -E "autonomous_extractor_min_confidence.*low.*medium.*high" "$CONSTRAINTS"
}
