#!/usr/bin/env bats
# Unit tests for eval-runner.sh and eval-config.sh

load '../helpers/test-helpers'

setup() {
  load '../helpers/test-helpers'
  EVAL_RUNNER="$PLUGIN_ROOT/evals/pipeline/eval-runner.sh"
}

@test "eval-runner exists and is executable" {
  [[ -x "$EVAL_RUNNER" ]]
}

@test "eval-runner has proper shebang" {
  head -1 "$EVAL_RUNNER" | grep -q '#!/usr/bin/env bash'
}

@test "eval-runner requires bash 4+" {
  grep -q 'BASH_VERSINFO\[0\]' "$EVAL_RUNNER"
}

@test "eval-runner no arguments exits 2 with usage" {
  run "$EVAL_RUNNER"
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"Usage"* ]]
}

@test "eval-runner invalid command exits 2" {
  run "$EVAL_RUNNER" invalid
  [[ "$status" -eq 2 ]]
}

@test "eval-runner run without --suite exits 2" {
  run "$EVAL_RUNNER" run
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"--suite"* ]]
}

@test "eval-runner list --suites shows available suites" {
  run "$EVAL_RUNNER" list --suites
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"lite"* ]]
  [[ "$output" == *"convergence"* ]]
  [[ "$output" == *"cost"* ]]
  [[ "$output" == *"compression"* ]]
  [[ "$output" == *"smoke"* ]]
}

@test "eval-runner list --baselines runs without error" {
  run "$EVAL_RUNNER" list --baselines
  [[ "$status" -eq 0 ]]
}

@test "eval-runner list --results runs without error" {
  run "$EVAL_RUNNER" list --results
  [[ "$status" -eq 0 ]]
}

@test "eval-config.sh is sourceable" {
  source "$PLUGIN_ROOT/evals/pipeline/eval-config.sh"
  [[ -n "$EVAL_DEFAULT_SUITE" ]]
  [[ -n "$EVAL_DEFAULT_TIMEOUT" ]]
  [[ -n "$EVAL_DEFAULT_PARALLEL" ]]
}

@test "eval-config validates timeout range" {
  source "$PLUGIN_ROOT/evals/pipeline/eval-config.sh"
  run eval_validate_config "timeout_per_task_minutes" 3
  [[ "$status" -ne 0 ]]
  run eval_validate_config "timeout_per_task_minutes" 30
  [[ "$status" -eq 0 ]]
  run eval_validate_config "timeout_per_task_minutes" 150
  [[ "$status" -ne 0 ]]
}

@test "eval-config validates parallel range" {
  source "$PLUGIN_ROOT/evals/pipeline/eval-config.sh"
  run eval_validate_config "parallel_tasks" 0
  [[ "$status" -ne 0 ]]
  run eval_validate_config "parallel_tasks" 3
  [[ "$status" -eq 0 ]]
  run eval_validate_config "parallel_tasks" 10
  [[ "$status" -ne 0 ]]
}

@test "eval-config validates regression threshold range" {
  source "$PLUGIN_ROOT/evals/pipeline/eval-config.sh"
  run eval_validate_config "regression_threshold_percent" 2
  [[ "$status" -ne 0 ]]
  run eval_validate_config "regression_threshold_percent" 20
  [[ "$status" -eq 0 ]]
  run eval_validate_config "regression_threshold_percent" 60
  [[ "$status" -ne 0 ]]
}

@test "eval-runner dry-run validates suite schema" {
  run "$EVAL_RUNNER" run --suite smoke --dry-run
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Validated"* ]]
}

@test "eval-runner dry-run rejects invalid suite name" {
  run "$EVAL_RUNNER" run --suite nonexistent --dry-run
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"Unknown suite"* ]]
}

@test "eval-runner dry-run reports fixture count" {
  run "$EVAL_RUNNER" run --suite smoke --dry-run
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Tasks"* || "$output" == *"tasks"* ]]
  [[ "$output" == *"Fixtures"* || "$output" == *"fixtures"* ]]
}

@test "eval-runner run without --live or --dry-run exits 2" {
  run "$EVAL_RUNNER" run --suite smoke
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"--live"* || "$output" == *"--dry-run"* ]]
}

@test "eval-runner live mode requires claude CLI" {
  # Build a restricted PATH that keeps python3 and bash but excludes claude.
  # python3 is required for suite validation before the claude check runs.
  local orig_path="$PATH"
  local restricted_path="/usr/bin:/bin"
  local py_path
  py_path="$(command -v python3 2>/dev/null || true)"
  if [[ -n "$py_path" ]]; then
    restricted_path="$(dirname "$py_path"):${restricted_path}"
  fi
  # Also include bash's directory to avoid subshell failures
  local bash_path
  bash_path="$(command -v bash 2>/dev/null || true)"
  if [[ -n "$bash_path" && "$(dirname "$bash_path")" != "/usr/bin" && "$(dirname "$bash_path")" != "/bin" ]]; then
    restricted_path="$(dirname "$bash_path"):${restricted_path}"
  fi
  PATH="$restricted_path"
  run "$EVAL_RUNNER" run --suite smoke --live
  PATH="$orig_path"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"claude"* ]]
}

@test "eval-runner save creates baseline file" {
  local result_file="${BATS_TEST_TMPDIR}/result.json"
  cat > "$result_file" <<'JSON'
{"suite":"smoke","version":"1.0.0","timestamp":"2026-04-14T10:00:00Z","duration_seconds":10,"environment":{"forge_version":"2.5.0","model":"sonnet","platform":"darwin"},"results":{"tasks":[],"aggregate":{"total":0,"passed":0,"failed":0,"errors":0,"pass_rate":0}}}
JSON

  local baseline_dir="${BATS_TEST_TMPDIR}/baselines"
  mkdir -p "$baseline_dir"

  run "$EVAL_RUNNER" save --baseline "test-bl" --from "$result_file" --baseline-dir "$baseline_dir"
  [[ "$status" -eq 0 ]]
  [[ -f "$baseline_dir/test-bl.json" ]]

  run python3 -c "
import json
b = json.load(open('$baseline_dir/test-bl.json'))
assert 'baseline_metadata' in b
assert b['baseline_metadata']['name'] == 'test-bl'
"
  [[ "$status" -eq 0 ]]
}

@test "eval-runner compare detects regression" {
  local baseline="${BATS_TEST_TMPDIR}/baseline.json"
  local current="${BATS_TEST_TMPDIR}/current.json"

  cat > "$baseline" <<'JSON'
{"baseline_metadata":{"name":"test"},"suite":"smoke","version":"1.0.0","timestamp":"2026-04-14T10:00:00Z","duration_seconds":10,"environment":{"forge_version":"2.5.0","model":"sonnet","platform":"darwin"},"results":{"tasks":[{"id":"py-01","language":"python","difficulty":"easy","result":"PASS","duration_seconds":30,"final_score":90}],"aggregate":{"total":1,"passed":1,"failed":0,"errors":0,"pass_rate":1.0}}}
JSON

  cat > "$current" <<'JSON'
{"suite":"smoke","version":"1.0.0","timestamp":"2026-04-14T11:00:00Z","duration_seconds":10,"environment":{"forge_version":"2.5.0","model":"sonnet","platform":"darwin"},"results":{"tasks":[{"id":"py-01","language":"python","difficulty":"easy","result":"FAIL","duration_seconds":30,"final_score":null}],"aggregate":{"total":1,"passed":0,"failed":1,"errors":0,"pass_rate":0.0}}}
JSON

  run "$EVAL_RUNNER" compare --baseline "$baseline" --current "$current" --format json
  [[ "$status" -eq 3 ]]
  echo "$output" | python3 -c "
import json, sys
c = json.load(sys.stdin)['comparison']
assert c['verdict'] == 'REGRESSION'
assert c['regression_count'] == 1
assert 'py-01' in c['aggregate']['regressions']
"
}

@test "eval-runner compare exits 0 when no regressions" {
  local baseline="${BATS_TEST_TMPDIR}/baseline.json"
  local current="${BATS_TEST_TMPDIR}/current.json"

  cat > "$baseline" <<'JSON'
{"baseline_metadata":{"name":"test"},"suite":"smoke","version":"1.0.0","timestamp":"2026-04-14T10:00:00Z","duration_seconds":10,"environment":{"forge_version":"2.5.0","model":"sonnet","platform":"darwin"},"results":{"tasks":[{"id":"py-01","language":"python","difficulty":"easy","result":"PASS","duration_seconds":30,"final_score":90}],"aggregate":{"total":1,"passed":1,"failed":0,"errors":0,"pass_rate":1.0}}}
JSON

  cat > "$current" <<'JSON'
{"suite":"smoke","version":"1.0.0","timestamp":"2026-04-14T11:00:00Z","duration_seconds":10,"environment":{"forge_version":"2.5.0","model":"sonnet","platform":"darwin"},"results":{"tasks":[{"id":"py-01","language":"python","difficulty":"easy","result":"PASS","duration_seconds":25,"final_score":92}],"aggregate":{"total":1,"passed":1,"failed":0,"errors":0,"pass_rate":1.0}}}
JSON

  run "$EVAL_RUNNER" compare --baseline "$baseline" --current "$current" --format json
  [[ "$status" -eq 0 ]]
}

@test "eval-config reads forge-config eval section" {
  local config_file="${BATS_TEST_TMPDIR}/forge-config.md"
  cat > "$config_file" <<'MD'
```yaml
eval:
  suite: smoke
  timeout_per_task_minutes: 15
  parallel_tasks: 2
  regression_threshold_percent: 10
```
MD

  source "$PLUGIN_ROOT/evals/pipeline/eval-config.sh"
  run eval_load_config "$config_file"
  [[ "$status" -eq 0 ]]
}

@test "eval-config rejects out-of-range values" {
  local config_file="${BATS_TEST_TMPDIR}/forge-config.md"
  cat > "$config_file" <<'MD'
```yaml
eval:
  timeout_per_task_minutes: 200
```
MD

  source "$PLUGIN_ROOT/evals/pipeline/eval-config.sh"
  run eval_load_config "$config_file"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"timeout_per_task_minutes"* ]]
}
