#!/usr/bin/env bats
# Contract tests for eval-report.sh

load '../helpers/test-helpers'

setup() {
  load '../helpers/test-helpers'
  EVAL_REPORT="$PLUGIN_ROOT/evals/pipeline/eval-report.sh"
}

@test "eval-report exists and is executable" {
  [[ -x "$EVAL_REPORT" ]]
}

@test "eval-report has proper shebang" {
  head -1 "$EVAL_REPORT" | grep -q '#!/usr/bin/env bash'
}

@test "eval-report no arguments exits 2" {
  run "$EVAL_REPORT"
  [[ "$status" -eq 2 ]]
}

@test "eval-report summary prints table for valid result" {
  local result_file="${BATS_TEST_TMPDIR}/result.json"
  cat > "$result_file" <<'JSON'
{"suite":"smoke","version":"1.0.0","timestamp":"2026-04-14T10:00:00Z","duration_seconds":10,"environment":{"forge_version":"2.5.0","model":"sonnet","platform":"darwin"},"results":{"tasks":[{"id":"py-01","language":"python","difficulty":"easy","result":"PASS","duration_seconds":30,"final_score":90,"tags":["dict"]}],"aggregate":{"total":1,"passed":1,"failed":0,"errors":0,"pass_rate":1.0,"quality_summary":{"avg_score":90,"total_tokens":45000,"total_cost_usd":0.18}}}}
JSON

  run "$EVAL_REPORT" summary "$result_file"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"py-01"* ]]
  [[ "$output" == *"PASS"* ]]
  [[ "$output" == *"100"* || "$output" == *"1.0"* ]]
}

@test "eval-report trend accepts multiple result files" {
  local r1="${BATS_TEST_TMPDIR}/r1.json"
  local r2="${BATS_TEST_TMPDIR}/r2.json"

  cat > "$r1" <<'JSON'
{"suite":"smoke","version":"1.0.0","timestamp":"2026-04-01T10:00:00Z","duration_seconds":10,"environment":{"forge_version":"2.5.0","model":"sonnet","platform":"darwin"},"results":{"tasks":[],"aggregate":{"total":1,"passed":0,"failed":1,"errors":0,"pass_rate":0.0,"quality_summary":{"avg_score":0,"total_tokens":50000,"total_cost_usd":0.20}}}}
JSON
  cat > "$r2" <<'JSON'
{"suite":"smoke","version":"1.0.0","timestamp":"2026-04-08T10:00:00Z","duration_seconds":10,"environment":{"forge_version":"2.5.0","model":"sonnet","platform":"darwin"},"results":{"tasks":[],"aggregate":{"total":1,"passed":1,"failed":0,"errors":0,"pass_rate":1.0,"quality_summary":{"avg_score":90,"total_tokens":45000,"total_cost_usd":0.18}}}}
JSON

  run "$EVAL_REPORT" trend --results "$r1" "$r2"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Trend"* || "$output" == *"trend"* ]]
}
