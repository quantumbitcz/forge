#!/usr/bin/env bats
# Asserts shared/intent-classification.md documents all 11 hybrid-grammar verbs
# and the concrete vague threshold. Spec §1, AC-S007.

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    DOC="$REPO_ROOT/shared/intent-classification.md"
}

@test "Hybrid-grammar verbs section is present" {
    grep -F "## Hybrid-grammar verbs" "$DOC"
}

@test "All 11 verbs are listed" {
    for verb in run fix sprint review verify deploy commit migrate bootstrap docs audit; do
        grep -E "^\| \`$verb\` \|" "$DOC"
    done
}

@test "Detection regex is documented" {
    grep -F 'run|fix|sprint|review|verify|deploy|commit|migrate|bootstrap|docs|audit' "$DOC"
}

@test "Vague threshold is concrete (signal-count < 2)" {
    grep -E "fewer than 2.*completeness signals|signal-count.*< 2|< 2.*signals" "$DOC"
}

@test "Vague routes to run mode" {
    # The vague outcome must explicitly route to run/BRAINSTORMING.
    grep -E "vague.*routes? to .*run|route.*run.*BRAINSTORMING" "$DOC"
}

@test "Priority table places explicit verb at the top" {
    # Look for the priority section and confirm the first item is the verb override.
    # Awk: enter the section after the heading line, exit at the next H2 boundary.
    awk '/^## Classification Priority/{flag=1;next} /^## /{flag=0} flag' "$DOC" \
        | grep -E "^1\. Explicit hybrid-grammar verb"
}
