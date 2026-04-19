# Pipeline evaluation harness

End-to-end eval harness that runs forge against 10 frozen scenarios on every
PR and every push to `master`. Complements `tests/evals/agents/` (reviewer I/O
tests) — this tree measures the full pipeline.

## Quick start

```bash
pip install -r tests/evals/pipeline/runner/requirements.txt

# Validate every scenario parses cleanly (fast, <5 s):
python -m tests.evals.pipeline.runner --collect-only

# Run the cheap smoke scenario in dry-run (no forge invocation):
FORGE_EVAL=1 python -m tests.evals.pipeline.runner --dry-run --no-baseline
```

## Directory shape

Each scenario is a directory with two required files and one optional bundle:

```
scenarios/<NN-slug>/
  prompt.md           # required — user-facing requirement text
  expected.yaml       # required — frozen expectations (pydantic-validated)
  fixtures/
    starter.tar.gz    # optional — seed worktree state before forge-init
```

## Schema

`expected.yaml` fields (all required):

| field                    | type                                                | notes                                       |
|--------------------------|-----------------------------------------------------|---------------------------------------------|
| `id`                     | str                                                 | must equal directory name                   |
| `mode`                   | `standard` \| `bugfix` \| `migration` \| `bootstrap`| pipeline mode                               |
| `token_budget`           | int > 0                                             | upper bound; over-budget degrades linearly  |
| `elapsed_budget_seconds` | int > 0                                             | wall-clock target                           |
| `min_pipeline_score`     | int [0, 100]                                        | floor for pipeline_score component          |
| `required_verdict`       | `PASS` \| `CONCERNS`                                | never FAIL in frozen scenarios              |
| `touched_files_expected` | list[str]                                           | overlap metric (reporting-only, Jaccard)    |
| `must_not_touch`         | list[str]                                           | glob patterns; match = hard fail            |
| `notes`                  | str                                                 | free-form                                   |

Field-name contract: **use `touched_files_expected` everywhere** (scenario YAML + `state.json.eval_run`). Do not introduce `touched_files` as an alias.

## Wall-clock budget

| knob                         | value   | meaning                                             |
|------------------------------|---------|-----------------------------------------------------|
| `scenario_timeout_seconds`   | 900 s   | per-scenario hard cap (15 min)                      |
| `total_budget_seconds`       | 2700 s  | full-suite hard ceiling (45 min)                    |
| CI `timeout-minutes`         | 50      | total_budget + 5 min overhead                       |
| SC1 target                   | ≤30 min | p90 of 10 consecutive master runs                   |

These four numbers are the **single source of truth** for the wall-clock contract (resolves review C1).

## Regression gate

On every PR run the runner compares the mean composite score to the latest `master` baseline (the most recent unexpired `eval-baseline-master-<sha>` workflow artifact).

- Delta ≥ `-regression_tolerance` (default `-3.0`) → **PASS**.
- Delta < `-regression_tolerance` → `EVAL-REGRESSION` CRITICAL, exit 1.
- Baseline unavailable (first master run, retention expiry, fetch failure) → `EVAL-BASELINE-UNAVAILABLE` WARNING, gate skipped, exit 0.

## Sanity check

Introduce a broken `expected.yaml` (e.g. set `mode: bogus`) in a throwaway branch. `python -m tests.evals.pipeline.runner --collect-only` must fail with a clear error naming the broken scenario. CI re-runs this on every push via the `collect` job.

## SC3 verification recipe

A deliberately regression-inducing PR (e.g. make the orchestrator skip VERIFY) must fail CI with **exit code 1** and the finding record `{"category":"EVAL-REGRESSION","severity":"CRITICAL",...}` present in `.forge/eval-results.jsonl`. Validated manually once before enforcement is enabled.

## Do not hand-edit `leaderboard.md`

`leaderboard.md` is rewritten on every `master` push by `.github/workflows/evals.yml`. If you need to change its shape, edit `runner/report.py` and push.
