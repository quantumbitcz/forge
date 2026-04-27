#!/usr/bin/env bats
# AC-8, AC-9, AC-9a: support-tier badges + idempotency.
load '../helpers/test-helpers'

@test "docs/support-tiers.md exists" {
  assert [ -f "$PLUGIN_ROOT/docs/support-tiers.md" ]
}

@test "docs/support-tiers.md defines three tiers" {
  run grep -E '^##\s+(CI-verified|Contract-verified|Community)\b' "$PLUGIN_ROOT/docs/support-tiers.md"
  assert_success
  [ "$(echo "$output" | wc -l | tr -d ' ')" -ge 3 ]
}

@test "every conventions.md has exactly one Support tier line under H1" {
  missing=0
  while IFS= read -r -d '' f; do
    lines=$(grep -cE '^>\s+Support tier:' "$f" || true)
    if [ "$lines" -ne 1 ]; then
      echo "$f has $lines Support tier lines"
      missing=1
    fi
  done < <(find "$PLUGIN_ROOT/modules" -type f \( -name 'conventions.md' \) -print0)
  [ "$missing" -eq 0 ]
}

@test "every module language file has a Support tier line" {
  missing=0
  for f in "$PLUGIN_ROOT"/modules/languages/*.md; do
    lines=$(grep -cE '^>\s+Support tier:' "$f" || true)
    if [ "$lines" -ne 1 ]; then
      echo "$f has $lines Support tier lines"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "every module testing file has a Support tier line" {
  missing=0
  for f in "$PLUGIN_ROOT"/modules/testing/*.md; do
    lines=$(grep -cE '^>\s+Support tier:' "$f" || true)
    if [ "$lines" -ne 1 ]; then
      echo "$f has $lines Support tier lines"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ]
}

@test "derive_support_tiers.py --check passes" {
  run python3 "$PLUGIN_ROOT/tests/lib/derive_support_tiers.py" --check --root "$PLUGIN_ROOT"
  assert_success
}

@test "derive_support_tiers.py is idempotent" {
  cp -r "$PLUGIN_ROOT" "$BATS_TEST_TMPDIR/repo"
  python3 "$BATS_TEST_TMPDIR/repo/tests/lib/derive_support_tiers.py" --root "$BATS_TEST_TMPDIR/repo"
  a="$(md5sum "$BATS_TEST_TMPDIR/repo/modules/languages/kotlin.md" | awk '{print $1}')"
  python3 "$BATS_TEST_TMPDIR/repo/tests/lib/derive_support_tiers.py" --root "$BATS_TEST_TMPDIR/repo"
  b="$(md5sum "$BATS_TEST_TMPDIR/repo/modules/languages/kotlin.md" | awk '{print $1}')"
  [ "$a" = "$b" ]
}
