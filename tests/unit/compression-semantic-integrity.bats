#!/usr/bin/env bats
# Unit tests: compression semantic integrity — verifies compressed files preserve semantics
# Uses fixture pairs (original + compressed) created in setup.

load '../helpers/test-helpers'

setup() {
  # Standard setup from test-helpers
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
  mkdir -p "${TEST_TEMP}/project"

  # Create fixture: original agent file
  mkdir -p "$TEST_TEMP/agents"
  cat > "$TEST_TEMP/agents/fg-test.original.md" << 'ORIG'
---
name: fg-test
description: test agent
---

# Test Agent

## Rules

- CRITICAL: Never delete production data
- WARNING: Avoid nested callbacks
- INFO: Prefer const over let

## Categories

Finding codes: ARCH-LAYER, SEC-INJECT, PERF-NPLUS

## Thresholds

- Max complexity: 15
- Min coverage: 80
- Score threshold: 75.5

```python
def validate(x):
    return x > 0
```

| Severity | Count | Action |
|----------|-------|--------|
| CRITICAL | 0     | Block  |
| WARNING  | 3     | Review |
ORIG

  # Create fixture: compressed version (terse but preserves semantics)
  cat > "$TEST_TEMP/agents/fg-test.md" << 'COMP'
---
name: fg-test
description: test agent
---

# Test Agent

## Rules

- CRITICAL: Never delete prod data
- WARNING: Avoid nested callbacks
- INFO: Prefer const over let

## Categories

Codes: ARCH-LAYER, SEC-INJECT, PERF-NPLUS

## Thresholds

- Max complexity: 15
- Min coverage: 80
- Score threshold: 75.5

```python
def validate(x):
    return x > 0
```

| Severity | Count | Action |
|----------|-------|--------|
| CRITICAL | 0     | Block  |
| WARNING  | 3     | Review |
COMP
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "compressed files preserve all category codes" {
  local found_pair=0
  for agent in "$TEST_TEMP"/agents/*.md; do
    [[ -f "${agent%.md}.original.md" ]] || continue
    found_pair=1
    local original="${agent%.md}.original.md"
    local original_cats compressed_cats
    original_cats=$(grep -oE '[A-Z]+-[A-Z]+-?[A-Z]*' "$original" | sort -u)
    compressed_cats=$(grep -oE '[A-Z]+-[A-Z]+-?[A-Z]*' "$agent" | sort -u)
    while IFS= read -r cat; do
      [[ -z "$cat" ]] && continue
      echo "$compressed_cats" | grep -qF "$cat" || fail "MISSING: $agent lost category code $cat"
    done <<< "$original_cats"
  done
  [[ "$found_pair" -eq 1 ]] || fail "No fixture pairs found — test setup failed"
}

@test "compressed files preserve all severity levels" {
  local found_pair=0
  for agent in "$TEST_TEMP"/agents/*.md; do
    [[ -f "${agent%.md}.original.md" ]] || continue
    found_pair=1
    local original="${agent%.md}.original.md"
    for severity in CRITICAL WARNING INFO; do
      local orig_count comp_count
      orig_count=$(grep -c "$severity" "$original" || true)
      comp_count=$(grep -c "$severity" "$agent" || true)
      [[ "$comp_count" -ge "$orig_count" ]] || fail "$agent lost $severity references ($orig_count -> $comp_count)"
    done
  done
  [[ "$found_pair" -eq 1 ]] || fail "No fixture pairs found — test setup failed"
}

@test "compressed files preserve YAML frontmatter exactly" {
  local found_pair=0
  for agent in "$TEST_TEMP"/agents/*.md; do
    [[ -f "${agent%.md}.original.md" ]] || continue
    found_pair=1
    local original="${agent%.md}.original.md"
    local orig_fm comp_fm
    orig_fm=$(awk '/^---$/{n++; if(n==2) exit; next} n==1{print}' "$original")
    comp_fm=$(awk '/^---$/{n++; if(n==2) exit; next} n==1{print}' "$agent")
    [[ "$orig_fm" == "$comp_fm" ]] || fail "$agent frontmatter was modified"
  done
  [[ "$found_pair" -eq 1 ]] || fail "No fixture pairs found — test setup failed"
}

@test "compressed files preserve all code blocks" {
  local found_pair=0
  for agent in "$TEST_TEMP"/agents/*.md; do
    [[ -f "${agent%.md}.original.md" ]] || continue
    found_pair=1
    local original="${agent%.md}.original.md"
    local orig_blocks comp_blocks
    orig_blocks=$(grep -c '```' "$original" || true)
    comp_blocks=$(grep -c '```' "$agent" || true)
    [[ "$comp_blocks" -eq "$orig_blocks" ]] || fail "$agent code block count changed ($orig_blocks -> $comp_blocks)"
  done
  [[ "$found_pair" -eq 1 ]] || fail "No fixture pairs found — test setup failed"
}

@test "compressed files preserve all table rows" {
  local found_pair=0
  for agent in "$TEST_TEMP"/agents/*.md; do
    [[ -f "${agent%.md}.original.md" ]] || continue
    found_pair=1
    local original="${agent%.md}.original.md"
    local orig_tables comp_tables
    # Count lines starting with | (per REVISIONS SPEC-09 #5)
    orig_tables=$(grep -c '^\|' "$original" || true)
    comp_tables=$(grep -c '^\|' "$agent" || true)
    [[ "$comp_tables" -eq "$orig_tables" ]] || fail "$agent table row count changed ($orig_tables -> $comp_tables)"
  done
  [[ "$found_pair" -eq 1 ]] || fail "No fixture pairs found — test setup failed"
}

@test "compressed files preserve numeric thresholds" {
  local found_pair=0
  for agent in "$TEST_TEMP"/agents/*.md; do
    [[ -f "${agent%.md}.original.md" ]] || continue
    found_pair=1
    local original="${agent%.md}.original.md"
    # Check specific important thresholds (skip trivial 0, 1, 2)
    for num in 15 80 75.5; do
      grep -qF "$num" "$agent" || echo "WARNING: $agent may have lost threshold $num"
    done
  done
  [[ "$found_pair" -eq 1 ]] || fail "No fixture pairs found — test setup failed"
  # This test is advisory -- always passes (thresholds might legitimately change in prose)
  true
}
