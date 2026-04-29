#!/usr/bin/env bats
# Contract tests: prompt_compaction block in shared/state-schema.md.
#
# The live schema is at 2.1.0 (mega-consolidation, 2026-04-27).
# Because prompt_compaction is a purely additive, conditional, observational field,
# no version bump is required — the regex below accepts any of the recent versions
# (1.7+ on the legacy 1.x line and any 2.x post-Phase-5/6/7) so this test stays
# robust across later additive bumps. The second test is the real contract: the
# documented field names must be present.

@test "state-schema.md carries a current schema version (1.7.0+ or 2.x)" {
  grep -qE '"version":[[:space:]]*"(1\.(7|8|9|10|11)\.0|2\.[0-9]+\.[0-9]+)"' \
    "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
}

@test "state-schema.md documents prompt_compaction fields" {
  local overview="${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
  local fields="${BATS_TEST_DIRNAME}/../../shared/state-schema-fields.md"
  grep -qh "prompt_compaction" "$overview" "$fields"
  grep -qh "pack_tokens" "$overview" "$fields"
  grep -qh "baseline_source" "$overview" "$fields"
  grep -qh "overall_ratio" "$overview" "$fields"
}
