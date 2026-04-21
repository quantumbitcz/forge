#!/usr/bin/env bats

@test "CLAUDE.md v2.0 features table includes Repo-map PageRank row" {
  grep -qE "Repo-map PageRank|Prompt compaction|prompt_compaction" \
    "${BATS_TEST_DIRNAME}/../../CLAUDE.md"
}

@test "CLAUDE.md supporting-systems list includes repomap.py" {
  grep -q "repomap" "${BATS_TEST_DIRNAME}/../../CLAUDE.md"
}

@test "rollout graduation doc documents 20-run gate" {
  local f="${BATS_TEST_DIRNAME}/../../shared/rollout/repomap-graduation.md"
  [ -f "$f" ]
  grep -q "20" "$f"
  grep -q "composite" "$f"
  grep -q "30 %" "$f" || grep -q "30%" "$f"
}
