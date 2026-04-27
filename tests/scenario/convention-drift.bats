#!/usr/bin/env bats
# Scenario tests: convention drift detection

# Covers:

load '../helpers/test-helpers'

QUALITY_GATE="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"

compute_hash() {
  local content="$1"
  printf '%s' "$content" | shasum -a 256 | cut -c1-8
}

@test "convention-drift: matching hashes = no warning" {
  local content="# Conventions\n\nDo: Use sealed interfaces\nDon't: Use var"
  local h1; h1=$(compute_hash "$content")
  local h2; h2=$(compute_hash "$content")
  [[ "$h1" == "$h2" ]] || fail "Same content should produce same hash"
}

@test "convention-drift: changed hash = drift detected" {
  local original="# Conventions\n\nDo: Use sealed interfaces"
  local modified="# Conventions\n\nDo: Use sealed interfaces\nDo: Use data classes"
  local h1; h1=$(compute_hash "$original")
  local h2; h2=$(compute_hash "$modified")
  [[ "$h1" != "$h2" ]] || fail "Different content should produce different hash"
}

@test "convention-drift: quality gate documents convention drift check" {
  grep -qi "convention.*drift\|conventions.*hash\|CONVENTION_DRIFT" "$QUALITY_GATE" \
    || fail "Convention drift check not documented in quality gate agent"
}

@test "convention-drift: quality gate documents using PREFLIGHT version on drift" {
  grep -qi "conventions_hash\|PREFLIGHT.*version\|state.json" "$QUALITY_GATE" \
    || fail "Quality gate does not document using PREFLIGHT version on drift"
}

@test "convention-drift: hash is deterministic SHA256 prefix" {
  local content="test content for hashing"
  local h1; h1=$(compute_hash "$content")
  local h2; h2=$(compute_hash "$content")
  [[ ${#h1} -eq 8 ]] || fail "Hash should be 8 chars, got ${#h1}"
  [[ "$h1" == "$h2" ]] || fail "Hash should be deterministic"
}

@test "convention-drift: empty content produces valid hash" {
  local hash; hash=$(compute_hash "")
  [[ ${#hash} -eq 8 ]] || fail "Empty content should still produce 8-char hash"
}
