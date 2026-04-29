#!/usr/bin/env bats
# Spec well-formedness regex (AC-S029).
# /forge run --spec <path> parses the spec for three required sections:
#   ## Objective | ## Goal | ## Goals
#   ## Scope | ## Non-goals
#   ## Acceptance Criteria | ## ACs

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# Helper: simulates the well-formedness check by running the three
# required regexes against a candidate file.
check_spec_wellformed() {
  local file="$1"
  grep -qE '^## (Objective|Goal|Goals)$' "$file" || return 1
  grep -qE '^## (Scope|Non-goals)$' "$file" || return 2
  grep -qE '^## (Acceptance [Cc]riteria|ACs)$' "$file" || return 3
  return 0
}

@test "well-formed spec with Objective + Scope + Acceptance Criteria passes" {
  cat > "$TMPDIR_TEST/good.md" <<'EOF'
# A spec

## Objective

Do X.

## Scope

In: x. Out: y.

## Acceptance Criteria

- AC-001: ...
EOF
  run check_spec_wellformed "$TMPDIR_TEST/good.md"
  [ "$status" -eq 0 ]
}

@test "alt heading 'Goals' is accepted in place of 'Objective'" {
  cat > "$TMPDIR_TEST/goals.md" <<'EOF'
## Goals

Do X.

## Non-goals

Don't do Y.

## ACs

- AC-001
EOF
  run check_spec_wellformed "$TMPDIR_TEST/goals.md"
  [ "$status" -eq 0 ]
}

@test "missing Objective fails with code 1" {
  cat > "$TMPDIR_TEST/no-obj.md" <<'EOF'
## Scope

In: x.

## Acceptance Criteria

- AC-001
EOF
  run check_spec_wellformed "$TMPDIR_TEST/no-obj.md"
  [ "$status" -eq 1 ]
}

@test "missing Scope/Non-goals fails with code 2" {
  cat > "$TMPDIR_TEST/no-scope.md" <<'EOF'
## Objective

Do X.

## Acceptance Criteria

- AC-001
EOF
  run check_spec_wellformed "$TMPDIR_TEST/no-scope.md"
  [ "$status" -eq 2 ]
}

@test "missing Acceptance Criteria fails with code 3" {
  cat > "$TMPDIR_TEST/no-ac.md" <<'EOF'
## Objective

Do X.

## Scope

In: x.
EOF
  run check_spec_wellformed "$TMPDIR_TEST/no-ac.md"
  [ "$status" -eq 3 ]
}

@test "case-sensitive Objective header — 'objective' (lowercase) fails" {
  cat > "$TMPDIR_TEST/bad-case.md" <<'EOF'
## objective

Lower case.

## Scope

x

## Acceptance Criteria

- AC
EOF
  run check_spec_wellformed "$TMPDIR_TEST/bad-case.md"
  [ "$status" -eq 1 ]
}

@test "lowercase 'criteria' is accepted (Acceptance criteria | ACs)" {
  cat > "$TMPDIR_TEST/lc-criteria.md" <<'EOF'
## Objective

x

## Scope

y

## Acceptance criteria

- AC
EOF
  run check_spec_wellformed "$TMPDIR_TEST/lc-criteria.md"
  [ "$status" -eq 0 ]
}
