"""Aggregate per-cell BenchmarkResult files into a single trends.jsonl line."""

from __future__ import annotations

import json
import statistics
from collections import defaultdict
from datetime import date
from pathlib import Path
from typing import Any


def _load_results(results_root: Path, week_of: date) -> list[dict[str, Any]]:
    day_dir = results_root / week_of.isoformat()
    if not day_dir.is_dir():
        return []
    return [json.loads(f.read_text()) for f in day_dir.glob("*.json")]


def _group_by_cell(
    results: list[dict[str, Any]],
) -> dict[tuple[str, str], list[dict[str, Any]]]:
    g: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for r in results:
        g[(r["os"], r["model"])].append(r)
    return g


def _compute_regressions(
    cells: list[dict[str, Any]],
    prior_trends_line: dict[str, Any] | None,
) -> list[dict[str, Any]]:
    """Cell-level regression detection vs prior week's trend line.

    Compares current `solve_rate_overall` per (os, model) against the same cell
    in the previous week's line. Emits entries with delta_pp <= -5; severity
    escalates to CRITICAL at -10pp, WARNING at -5pp.
    """
    if prior_trends_line is None:
        return []
    prior_by_cell: dict[tuple[str, str], float] = {}
    for c in prior_trends_line.get("cells", []):
        prior_by_cell[(c["os"], c["model"])] = float(c.get("solve_rate_overall", 0.0))

    regressions: list[dict[str, Any]] = []
    for cell in cells:
        key = (cell["os"], cell["model"])
        if key not in prior_by_cell:
            continue
        prev = prior_by_cell[key]
        curr = float(cell.get("solve_rate_overall", 0.0))
        delta_pp = (curr - prev) * 100
        if delta_pp > -5:
            continue
        severity = "CRITICAL" if delta_pp <= -10 else "WARNING"
        regressions.append(
            {
                "os": cell["os"],
                "model": cell["model"],
                "prev_solve_rate": prev,
                "curr_solve_rate": curr,
                "delta_pp": delta_pp,
                "severity": severity,
            }
        )
    return regressions


def aggregate_week(
    *,
    results_root: Path,
    week_of: date,
    commit_sha: str,
    forge_version: str,
    hook_failures_total: int,
    prior_trends_line: dict[str, Any] | None = None,
    cost_truncated: bool = False,
) -> dict[str, Any]:
    all_results = _load_results(results_root, week_of)
    cells = []
    for (os_name, model), rs in sorted(_group_by_cell(all_results).items()):
        solved_runs = [r for r in rs if r["solved"]]
        timed = sum(1 for r in rs if r["timeout"])
        docker_sk = sum(1 for r in rs if r.get("error") == "BENCH-DOCKER-SKIPPED")
        per_complexity: dict[str, list[bool]] = defaultdict(list)
        for r in rs:
            # Hard-require real `complexity` — no silent "S" fallback. Missing
            # field means the result came from a pre-contract writer; bail loudly.
            per_complexity[r["complexity"]].append(r["solved"])
        costs_solved = [r["cost_usd"] for r in solved_runs if r["cost_usd"] > 0]
        unverifiable_total = sum(int(r.get("unverifiable_count", 0)) for r in rs)
        cells.append(
            {
                "os": os_name,
                "model": model,
                "entries_total": len(rs),
                "entries_solved": len(solved_runs),
                "entries_timeout": timed,
                "entries_docker_skipped": docker_sk,
                "solve_rate_overall": len(solved_runs) / len(rs) if rs else 0.0,
                "solve_rate_by_complexity": {
                    k: (sum(v) / len(v) if v else 0.0) for k, v in sorted(per_complexity.items())
                },
                "median_cost_per_solve_usd": statistics.median(costs_solved)
                if costs_solved
                else 0.0,
                "total_cost_usd": sum(r["cost_usd"] for r in rs),
                "unverifiable_total": unverifiable_total,
            }
        )

    regressions = _compute_regressions(cells, prior_trends_line)
    out: dict[str, Any] = {
        "schema_version": 1,
        "week_of": week_of.isoformat(),
        "commit_sha": commit_sha,
        "forge_version": forge_version,
        "cells": cells,
        "hook_failures_total": hook_failures_total,
        "regressions": regressions,
    }
    if cost_truncated:
        out["cost_truncated"] = True
    return out


def append_trends(trends_path: Path, line: dict[str, Any], *, validate: bool = False) -> None:
    """Append one JSON line to trends.jsonl (create if missing).

    Args:
        validate: when True, validate `line` against trends_line.schema.json
            before writing. Default off for perf; CI calls with validate=True.
    """
    if validate:
        from jsonschema import Draft202012Validator

        schema_path = Path(__file__).parent / "schemas" / "trends_line.schema.json"
        validator = Draft202012Validator(json.loads(schema_path.read_text(encoding="utf-8")))
        validator.validate(line)
    trends_path.parent.mkdir(parents=True, exist_ok=True)
    with trends_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(line, sort_keys=True) + "\n")


def count_hook_failures(artifacts_root: Path) -> int:
    total = 0
    for log in artifacts_root.rglob(".hook-failures.jsonl"):
        with log.open(encoding="utf-8") as f:
            total += sum(1 for line in f if line.strip())
    return total


def _read_last_trends_line(trends_path: Path) -> dict[str, Any] | None:
    """Read the most recent JSON line from trends.jsonl, or None if absent."""
    if not trends_path.is_file():
        return None
    last: str | None = None
    with trends_path.open(encoding="utf-8") as f:
        for raw in f:
            if raw.strip():
                last = raw
    if last is None:
        return None
    parsed: dict[str, Any] = json.loads(last)
    return parsed


def main(argv: list[str] | None = None) -> int:
    import argparse
    from datetime import date as _date

    p = argparse.ArgumentParser()
    p.add_argument("--results-root", type=Path, required=True)
    p.add_argument("--trends", type=Path, required=True)
    p.add_argument("--commit-sha", type=str, required=True)
    p.add_argument("--forge-version", type=str, required=True)
    args = p.parse_args(argv)
    prior = _read_last_trends_line(args.trends)
    line = aggregate_week(
        results_root=args.results_root,
        week_of=_date.today(),
        commit_sha=args.commit_sha,
        forge_version=args.forge_version,
        hook_failures_total=count_hook_failures(args.results_root),
        prior_trends_line=prior,
    )
    append_trends(args.trends, line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
