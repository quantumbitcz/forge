"""CLI: ``python -m tests.evals.pipeline.runner``.

Modes:
    --collect-only   — discover + validate scenarios, exit 0/1. No forge invocation.
    --dry-run        — validate harness plumbing (discovery + scoring + report +
                       baseline) against the first scenario; synthesizes a
                       DRY_RUN Result without invoking the ``claude`` CLI. Used
                       as a CI smoke test on runners that lack Claude Code.
    (default)        — run all scenarios sequentially, invoking forge via the
                       ``claude`` CLI; write JSONL + leaderboard; run regression
                       gate against master baseline.

Exit codes:
    0   success (all scenarios ran; regression gate passed or skipped)
    1   collection failed, scenario errored, or regression gate tripped
    2   invalid CLI arguments
"""
from __future__ import annotations

import argparse
import datetime as _dt
import os
import sys
from pathlib import Path

from tests.evals.pipeline.runner.baseline import (
    BaselineUnavailable,
    compute_gate,
    fetch_baseline_from_github,
)
from tests.evals.pipeline.runner.executor import execute_scenario
from tests.evals.pipeline.runner.report import write_jsonl, write_leaderboard
from tests.evals.pipeline.runner.scenarios import (
    ScenarioCollectionError,
    discover_scenarios,
)
from tests.evals.pipeline.runner.schema import Finding, Result
from tests.evals.pipeline.runner.scoring import (
    composite_score,
    elapsed_adherence,
    jaccard_overlap,
    token_adherence,
)


DEFAULT_SCENARIOS_ROOT = Path(__file__).resolve().parents[1] / "scenarios"
DEFAULT_RESULTS_PATH = Path(".forge") / "eval-results.jsonl"
DEFAULT_LEADERBOARD_PATH = Path(__file__).resolve().parents[1] / "leaderboard.md"


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m tests.evals.pipeline.runner")
    p.add_argument("--collect-only", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument(
        "--scenarios-root", type=Path, default=DEFAULT_SCENARIOS_ROOT
    )
    p.add_argument(
        "--forge-root",
        type=Path,
        default=Path(__file__).resolve().parents[3].parent,
        help="Path to forge plugin checkout (symlinked into each scenario).",
    )
    p.add_argument(
        "--results-path", type=Path, default=DEFAULT_RESULTS_PATH
    )
    p.add_argument(
        "--leaderboard-path", type=Path, default=DEFAULT_LEADERBOARD_PATH
    )
    p.add_argument("--scenario-timeout-seconds", type=int, default=900)
    p.add_argument("--total-budget-seconds", type=int, default=2700)
    p.add_argument("--regression-tolerance", type=float, default=3.0)
    p.add_argument("--baseline-repo", type=str, default="quantumbitcz/forge")
    p.add_argument("--baseline-branch", type=str, default="master")
    p.add_argument(
        "--no-baseline",
        action="store_true",
        help="Skip baseline fetch (for local dry runs); gate becomes pass-with-warning.",
    )
    p.add_argument(
        "--commit-sha",
        type=str,
        default=os.environ.get("GITHUB_SHA", "local"),
    )
    return p


def _score_one(scenario, raw) -> Result:
    exp = scenario.expected
    tok_adh = token_adherence(raw.tokens, exp.token_budget) if raw.tokens else 0.0
    el_adh = elapsed_adherence(
        raw.elapsed_seconds, exp.elapsed_budget_seconds
    ) if raw.elapsed_seconds else 0.0
    overlap = jaccard_overlap(exp.touched_files_expected, raw.touched_files_actual)
    composite = composite_score(
        pipeline_score=raw.pipeline_score, token_adh=tok_adh, elapsed_adh=el_adh
    )
    findings: list[Finding] = []
    if raw.timed_out:
        findings.append(Finding(
            category="EVAL-TIMEOUT", severity="CRITICAL",
            message=f"scenario exceeded {exp.elapsed_budget_seconds}s budget",
        ))
    if raw.must_not_touch_violations:
        findings.append(Finding(
            category="EVAL-MUST-NOT-TOUCH", severity="CRITICAL",
            message=f"modified forbidden paths: {raw.must_not_touch_violations}",
        ))
    if raw.verdict not in (exp.required_verdict, "PASS"):
        findings.append(Finding(
            category="EVAL-VERDICT-MISMATCH", severity="WARNING",
            message=f"verdict {raw.verdict} < required {exp.required_verdict}",
        ))
    if raw.tokens > exp.token_budget or raw.elapsed_seconds > exp.elapsed_budget_seconds:
        findings.append(Finding(
            category="EVAL-BUDGET-OVER", severity="WARNING",
            message=(
                f"budget exceeded: tokens {raw.tokens}/{exp.token_budget}, "
                f"elapsed {raw.elapsed_seconds}/{exp.elapsed_budget_seconds}s"
            ),
        ))
    if overlap < 0.5:
        findings.append(Finding(
            category="EVAL-OVERLAP-LOW", severity="INFO",
            message=f"touched-file Jaccard {overlap:.2f} < 0.5",
        ))
    status = (
        "timeout" if raw.timed_out
        else "error" if raw.error
        else "completed"
    )
    return Result(
        scenario_id=raw.scenario_id,
        started_at=raw.started_at,
        ended_at=raw.ended_at,
        actual_tokens=raw.tokens,
        actual_elapsed_seconds=raw.elapsed_seconds,
        pipeline_score=raw.pipeline_score,
        verdict=raw.verdict if raw.verdict in ("PASS", "CONCERNS", "FAIL") else "FAIL",
        touched_files_actual=raw.touched_files_actual,
        overlap_jaccard=overlap,
        token_adherence=tok_adh,
        elapsed_adherence=el_adh,
        composite=composite,
        findings=findings,
        status=status,
    )


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)

    try:
        scenarios = discover_scenarios(args.scenarios_root)
    except ScenarioCollectionError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    print(f"discovered {len(scenarios)} scenarios", file=sys.stderr)
    if args.collect_only:
        return 0

    results: list[Result] = []
    if args.dry_run and scenarios:
        scenarios = scenarios[:1]   # smoke: first scenario only

    for s in scenarios:
        if args.dry_run:
            # Smoke test: validate discovery + scoring/report plumbing without
            # invoking the `claude` CLI (not present on CI runners). Produces a
            # DRY_RUN record that downstream report + gate logic can consume.
            now = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            result = Result(
                scenario_id=s.id,
                started_at=now,
                ended_at=now,
                actual_tokens=0,
                actual_elapsed_seconds=0,
                pipeline_score=0.0,
                verdict="DRY_RUN",
                touched_files_actual=[],
                overlap_jaccard=0.0,
                token_adherence=0.0,
                elapsed_adherence=0.0,
                composite=0.0,
                findings=[],
                status="dry_run",
            )
        else:
            raw = execute_scenario(
                scenario=s,
                forge_root=args.forge_root,
                dry_run=False,
                scenario_timeout_seconds=args.scenario_timeout_seconds,
            )
            result = _score_one(s, raw)
        results.append(result)

    write_jsonl(results, args.results_path)
    write_leaderboard(results, args.commit_sha, args.leaderboard_path)

    # Regression gate
    if args.no_baseline:
        baseline: list[dict] | None = None
    else:
        try:
            baseline = fetch_baseline_from_github(
                repo=args.baseline_repo, branch=args.baseline_branch
            )
        except BaselineUnavailable as e:
            print(f"baseline unavailable: {e}", file=sys.stderr)
            baseline = None

    decision = compute_gate(
        current=[r.model_dump() for r in results],
        baseline=baseline,
        tolerance=args.regression_tolerance,
    )
    if decision.finding is not None:
        print(
            f"[{decision.finding.severity}] {decision.finding.category}: "
            f"{decision.finding.message}",
            file=sys.stderr,
        )

    if not decision.passed:
        return 1

    any_critical = any(
        f.severity == "CRITICAL" for r in results for f in r.findings
    )
    return 1 if any_critical else 0


if __name__ == "__main__":
    raise SystemExit(main())
