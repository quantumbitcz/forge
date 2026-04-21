# EVAL-* scoring categories

Emitted by the pipeline evaluation harness at `tests/evals/pipeline/runner/`
(NOT by in-pipeline review agents). Findings live in
`.forge/eval-results.jsonl` and the GitHub Actions workflow log — they are
excluded from in-run pipeline scoring (they measure the eval run, not the
code change).

| Code | Severity | Meaning |
|---|---|---|
| `EVAL-REGRESSION` | CRITICAL | Composite dropped > `evals.regression_tolerance` vs master baseline |
| `EVAL-TIMEOUT` | CRITICAL | Scenario exceeded `evals.scenario_timeout_seconds` (default 900 s) |
| `EVAL-MUST-NOT-TOUCH` | CRITICAL | Pipeline modified a path listed in scenario `must_not_touch` |
| `EVAL-VERDICT-MISMATCH` | WARNING | Actual verdict worse than scenario `required_verdict` |
| `EVAL-BUDGET-OVER` | WARNING | Tokens or elapsed over scenario budget (even if adherence > 0) |
| `EVAL-OVERLAP-LOW` | INFO | Jaccard(`touched_files_expected`, actual) < 0.5 |
| `EVAL-BASELINE-UNAVAILABLE` | WARNING | master baseline artifact missing; regression gate skipped |

## Field name contract (review C2)

Scenario YAML and state schema use the **single key** `touched_files_expected`
in both places. Do not introduce `touched_files` as an alias.
