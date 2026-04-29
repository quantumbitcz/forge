# Phase 8 — Weekly benchmark

This harness measures how often forge solves real, user-authored feature requests. The result is a weekly-committed `SCORECARD.md` at repo root.

## Operator workflows

### Curate a new corpus entry

```bash
python -m tests.evals.benchmark.curate \
  --db "$HOME/.forge/run-history.db" \
  --source-repo "$HOME/Projects/myapp"
```

Per candidate, confirm complexity, tags, Docker detection, and each PII match. Writes `corpus/<date>-<slug>/`.

### Run the benchmark (dry-run — no claude CLI needed)

```bash
python -m tests.evals.benchmark.runner \
  --corpus-root tests/evals/benchmark/corpus \
  --results-root tests/evals/benchmark/results \
  --os ubuntu-latest --model claude-sonnet-4-6 --dry-run
```

### Render SCORECARD.md locally

```bash
python -m tests.evals.benchmark.render_scorecard \
  --trends tests/evals/benchmark/trends.jsonl \
  --output SCORECARD.md
```

### Refresh baseline after an improvement

```bash
python -m tests.evals.benchmark.refresh_baseline \
  --trends tests/evals/benchmark/trends.jsonl \
  --output tests/evals/benchmark/baseline.json \
  --confirm --commit-sha "$(git rev-parse HEAD)"
```

## CI

`.github/workflows/benchmark.yml` runs Monday 06:00 UTC. 6 matrix cells: `{ubuntu-latest, macos-latest, windows-latest} × {claude-sonnet-4-6, claude-opus-4-7}`.

Release gate: `PHASE_8_CORPUS_GATE=1` is set automatically by the weekly cron (`github.event_name == 'schedule'` in `benchmark.yml`). It enforces `>= 10` corpus entries + distribution spread (AC-801). `workflow_dispatch` runs and local `pytest` invocations leave it unset and skip the gate — useful for single-entry debugging before the corpus is complete.

## See also

- ADR: `docs/adr/0013-weekly-benchmark-extension.md`
- Fast smoke tier: `tests/evals/pipeline/README.md`
