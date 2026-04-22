#!/usr/bin/env bats
# Contract tests: prompt_compaction block in shared/state-schema.md.
#
# The live schema is at 1.10.0 (session-handoff tracking).
# Because prompt_compaction is a purely additive, conditional, observational field,
# no version bump is required — the regex below accepts any of the recent versions
# so this test stays robust across later additive bumps. The second test is the
# real contract: the documented field names must be present.

@test "state-schema.md carries a current schema version (1.7.0 or later)" {
  grep -qE '1\.(7|8|9|10|11)\.0' \
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
