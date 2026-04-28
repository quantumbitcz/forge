#!/usr/bin/env bats
# Asserts shared/state-schema.md, shared/state-transitions.md, and
# shared/stage-contract.md document the mega-consolidation schema bump.
#
# Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §11.
# ACs:  AC-S024, AC-S025 (event-name slots), AC-S026.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCHEMA="$REPO_ROOT/shared/state-schema.md"
    TRANS="$REPO_ROOT/shared/state-transitions.md"
    STAGE="$REPO_ROOT/shared/stage-contract.md"
}

@test "state-schema.md version is at least 1.11.0" {
    # Accept 1.11.x, 2.x, or higher — anything greater than the pre-bump 1.10.x.
    grep -E '^\*\*Version:\*\* (1\.(1[1-9]|[2-9][0-9])|[2-9])\.' "$SCHEMA"
}

@test "state.brainstorm object is documented" {
    grep -F "state.brainstorm" "$SCHEMA"
    grep -F "spec_path" "$SCHEMA"
    grep -F "original_input" "$SCHEMA"
    grep -F "section_approvals" "$SCHEMA"
}

@test "state.bug.hypotheses schema is documented" {
    grep -F "state.bug" "$SCHEMA"
    grep -F "falsifiability_test" "$SCHEMA"
    grep -F "evidence_required" "$SCHEMA"
    grep -F "posterior" "$SCHEMA"
    grep -E "status.*untested.*testing.*tested.*dropped" "$SCHEMA"
}

@test "state.feedback_decisions schema is documented" {
    grep -F "state.feedback_decisions" "$SCHEMA"
    grep -E "verdict.*actionable.*wrong.*preference" "$SCHEMA"
    grep -E "addressed.*actionable_routed.*defended.*acknowledged" "$SCHEMA"
}

@test "state.platform schema is documented" {
    grep -F "state.platform" "$SCHEMA"
    grep -E "name.*github.*gitlab.*bitbucket.*gitea.*unknown" "$SCHEMA"
    grep -F "auth_method" "$SCHEMA"
}

@test "BRAINSTORMING enum value is documented" {
    grep -F "BRAINSTORMING" "$SCHEMA"
}

@test "OTel event names registered" {
    for ev in forge.brainstorm.started forge.brainstorm.question_asked \
              forge.brainstorm.approaches_proposed forge.brainstorm.spec_written \
              forge.brainstorm.completed forge.brainstorm.aborted; do
        grep -F "$ev" "$SCHEMA"
    done
}

@test "state-transitions.md lists BRAINSTORMING in the canonical state set" {
    grep -F "BRAINSTORMING" "$TRANS"
}

@test "PREFLIGHT -> BRAINSTORMING transition row exists" {
    grep -E '\| `PREFLIGHT` \|.*\| `BRAINSTORMING` \|' "$TRANS"
}

@test "BRAINSTORMING -> EXPLORING transition row exists" {
    grep -E '\| `BRAINSTORMING` \|.*\| `EXPLORING` \|' "$TRANS"
}

@test "BRAINSTORMING -> ABORTED transition row exists" {
    grep -E '\| `BRAINSTORMING` \|.*\| `ABORTED` \|' "$TRANS"
}

@test "BRAINSTORMING self-loop transition row exists" {
    # current=BRAINSTORMING and next also BRAINSTORMING — resume from cache.
    grep -E '\| `BRAINSTORMING` \|.*resume_with_cache.*\| `BRAINSTORMING` \|' "$TRANS"
}

@test "stage-contract.md declares BRAINSTORMING between PREFLIGHT and EXPLORE" {
    [ -f "$STAGE" ]
    grep -F "BRAINSTORMING" "$STAGE"
    # The overview table must show BRAINSTORMING as a row indexed 0.5 (conditional).
    grep -E '\| 0\.5 \| BRAINSTORMING' "$STAGE"
}
