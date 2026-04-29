"""Benchmark runner: per-cell execution of the corpus.

Dry-run mode mirrors tests/evals/pipeline/runner/__main__.py — discovers entries,
writes DRY_RUN placeholder results, exits 0. No `claude` CLI required.

Live mode calls tests.evals.pipeline.runner.executor.execute_scenario after
writing model overrides and seeding Phase 7 AC injection.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from tests.evals.benchmark.cost_guard import CostGuard
from tests.evals.benchmark.discovery import CorpusValidationError, discover_corpus
from tests.evals.benchmark.result import BenchmarkResult


def _write_result(results_root: Path, r: BenchmarkResult) -> Path:
    day_dir = results_root / r.run_date
    day_dir.mkdir(parents=True, exist_ok=True)
    safe_model = r.model.replace("/", "_")
    out = day_dir / f"{r.entry_id}.{r.os}.{safe_model}.json"
    out.write_text(json.dumps(r.to_dict(), indent=2, sort_keys=True), encoding="utf-8")
    return out


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m tests.evals.benchmark.runner")
    p.add_argument("--corpus-root", type=Path, required=True)
    p.add_argument("--results-root", type=Path, required=True)
    p.add_argument(
        "--os", type=str, required=True, choices=["ubuntu-latest", "macos-latest", "windows-latest"]
    )
    p.add_argument("--model", type=str, required=True)
    # Kept for workflow YAML compatibility; runner is single-threaded today.
    # Workflow passes `--parallel 1`; removing the flag would break it.
    p.add_argument("--parallel", type=int, default=1)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--forge-root", type=Path, default=Path(__file__).resolve().parents[3])
    p.add_argument("--entry-filter", type=str, default="", help="substring filter on entry id")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    assert args.parallel == 1, "parallelism not yet implemented"

    # CostGuard tracks cumulative spend across this cell and aborts the loop
    # once the weekly ceiling is reached. Default $200 mirrors cost_guard.py.
    guard = CostGuard(max_weekly_cost_usd=200.0)

    try:
        entries = discover_corpus(args.corpus_root, os_name=args.os)
    except CorpusValidationError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    if args.entry_filter:
        entries = [e for e in entries if args.entry_filter in e.entry_id]

    print(f"discovered {len(entries)} corpus entries", file=sys.stderr)

    for entry in entries:
        if args.dry_run:
            r = BenchmarkResult.dry_run(
                entry_id=entry.entry_id,
                os=args.os,
                model=args.model,
                complexity=entry.complexity,
            )
            _write_result(args.results_root, r)
            continue

        # Live path added in Task 10.
        from tests.evals.benchmark.live_run import run_one_entry

        r = run_one_entry(
            entry=entry, forge_root=args.forge_root, model=args.model, os_name=args.os
        )
        _write_result(args.results_root, r)
        guard.record(r.cost_usd)
        if not guard.within_limit():
            print(
                f"BENCH-COST-CEILING: ${guard.total_usd:.2f} >= ${guard.max_weekly_cost_usd:.2f}",
                file=sys.stderr,
            )
            # TODO(phase8-review): wire cost_truncated through workflow
            break

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
