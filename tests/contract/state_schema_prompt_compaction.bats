#!/usr/bin/env bats
# Contract tests: prompt_compaction block in shared/state-schema.md.
#
# The live schema is at 1.9.0 (Phase 11 self-consistency + Phase 14 time-travel).
# Because prompt_compaction is a purely additive, conditional, observational field,
# no version bump is required — the regex below accepts any of the recent versions
# so this test stays robust across later additive bumps. The second test is the
# real contract: the documented field names must be present.

@test "state-schema.md carries a current schema version (1.7.0 or later)" {
  grep -qE '1\.(7|8|9|10|11)\.0' \
    "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
}

@test "state-schema.md documents prompt_compaction fields" {
  grep -q "prompt_compaction" "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
  grep -q "pack_tokens" "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
  grep -q "baseline_source" "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
  grep -q "overall_ratio" "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
}
