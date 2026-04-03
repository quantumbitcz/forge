#!/usr/bin/env bats
# Contract tests: shared/git-conventions.md — validates the git conventions document.

load '../helpers/test-helpers'

GIT_CONV="$PLUGIN_ROOT/shared/git-conventions.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "git-conventions: document exists" {
  [[ -f "$GIT_CONV" ]]
}

# ---------------------------------------------------------------------------
# 2. Branch naming template documented
# ---------------------------------------------------------------------------
@test "git-conventions: branch naming template {type}/{ticket}-{slug} documented" {
  grep -q '{type}/{ticket}-{slug}' "$GIT_CONV" \
    || fail "Branch naming template '{type}/{ticket}-{slug}' not found"
}

# ---------------------------------------------------------------------------
# 3. All 4 core branch types documented
# ---------------------------------------------------------------------------
@test "git-conventions: branch types feat, fix, refactor, chore all documented" {
  for btype in feat fix refactor chore; do
    grep -q "\b${btype}\b" "$GIT_CONV" \
      || fail "Branch type '${btype}' not found in git-conventions.md"
  done
}

# ---------------------------------------------------------------------------
# 4. ticket_source auto resolution documented
# ---------------------------------------------------------------------------
@test "git-conventions: ticket_source auto resolution documented" {
  grep -q "ticket_source" "$GIT_CONV" \
    || fail "'ticket_source' field not documented"
  grep -q "auto" "$GIT_CONV" \
    || fail "'ticket_source: auto' resolution not documented"
  grep -qi "linear\|Linear ID" "$GIT_CONV" \
    || fail "Linear ID resolution not documented for ticket_source auto"
  grep -qi "kanban" "$GIT_CONV" \
    || fail "Kanban ticket resolution not documented for ticket_source auto"
}

# ---------------------------------------------------------------------------
# 5. Conventional Commits format documented
# ---------------------------------------------------------------------------
@test "git-conventions: conventional commits format documented" {
  grep -qi "conventional commit\|Conventional Commits" "$GIT_CONV" \
    || fail "Conventional Commits format not mentioned"
  grep -q '{type}({scope}): {description}' "$GIT_CONV" \
    || fail "Commit format template '{type}({scope}): {description}' not found"
}

# ---------------------------------------------------------------------------
# 6. No AI attribution rule documented (NEVER + Co-Authored-By)
# ---------------------------------------------------------------------------
@test "git-conventions: no AI attribution rule documented with NEVER and Co-Authored-By" {
  grep -q "NEVER\|Never" "$GIT_CONV" \
    || fail "NEVER prohibition section not found"
  grep -q "Co-Authored-By" "$GIT_CONV" \
    || fail "'Co-Authored-By' prohibition not documented"
}

# ---------------------------------------------------------------------------
# 7. All 8 commit_types listed
# ---------------------------------------------------------------------------
@test "git-conventions: all 8 commit_types listed (feat fix chore refactor docs test perf ci)" {
  for ctype in feat fix chore refactor docs test perf ci; do
    grep -q "\b${ctype}\b" "$GIT_CONV" \
      || fail "commit_type '${ctype}' not found in git-conventions.md"
  done
}

# ---------------------------------------------------------------------------
# 8. Hook detection section exists
# ---------------------------------------------------------------------------
@test "git-conventions: hook detection section exists" {
  grep -qi "Hook Detection\|hook detection" "$GIT_CONV" \
    || fail "Hook Detection section not found"
}

# ---------------------------------------------------------------------------
# 9. All 6 hook tools documented
# ---------------------------------------------------------------------------
@test "git-conventions: all 6 hook tools documented (Husky pre-commit Lefthook commitlint Commitizen Native git hook)" {
  grep -qi "husky" "$GIT_CONV" \
    || fail "Husky not documented in hook detection"
  grep -qi "pre-commit" "$GIT_CONV" \
    || fail "pre-commit not documented in hook detection"
  grep -qi "lefthook" "$GIT_CONV" \
    || fail "Lefthook not documented in hook detection"
  grep -qi "commitlint" "$GIT_CONV" \
    || fail "commitlint not documented in hook detection"
  grep -qi "commitizen\|czrc\|cz\.json" "$GIT_CONV" \
    || fail "Commitizen not documented in hook detection"
  grep -qi "native git hook\|\.git/hooks" "$GIT_CONV" \
    || fail "Native git hook not documented in hook detection"
}

# ---------------------------------------------------------------------------
# 10. Respect rule documented
# ---------------------------------------------------------------------------
@test "git-conventions: respect rule documented (Never override existing project hooks)" {
  grep -qi "never override existing project hooks\|Never override existing" "$GIT_CONV" \
    || fail "Respect rule 'Never override existing project hooks' not found"
}

# ---------------------------------------------------------------------------
# 11. Small commit strategy documented
# ---------------------------------------------------------------------------
@test "git-conventions: small commit strategy documented" {
  grep -qi "small commit\|commit strategy\|architectural layer" "$GIT_CONV" \
    || fail "Small commit strategy not documented"
  # At least domain and api layers should be mentioned
  grep -q "domain" "$GIT_CONV" \
    || fail "Domain layer not mentioned in commit strategy"
  grep -q "api\|API" "$GIT_CONV" \
    || fail "API layer not mentioned in commit strategy"
}

# ---------------------------------------------------------------------------
# 12. forge.local.md git section documented
# ---------------------------------------------------------------------------
@test "git-conventions: forge.local.md git section documented" {
  grep -q "forge\.local\.md" "$GIT_CONV" \
    || fail "forge.local.md not referenced"
  grep -q "git:" "$GIT_CONV" \
    || fail "git: configuration section not documented"
}
