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


def _group_by_cell(results: list[dict]) -> dict[tuple[str, str], list[dict]]:
    g: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for r in results:
        g[(r["os"], r["model"])].append(r)
    return g


def aggregate_week(*, results_root: Path, week_of: date, commit_sha: str,
                   forge_version: str, hook_failures_total: int) -> dict[str, Any]:
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
        cells.append({
            "os": os_name, "model": model,
            "entries_total": len(rs),
            "entries_solved": len(solved_runs),
            "entries_timeout": timed,
            "entries_docker_skipped": docker_sk,
            "solve_rate_overall": len(solved_runs) / len(rs) if rs else 0.0,
            "solve_rate_by_complexity": {
                k: (sum(v) / len(v) if v else 0.0) for k, v in sorted(per_complexity.items())
            },
            "median_cost_per_solve_usd": statistics.median(costs_solved) if costs_solved else 0.0,
            "total_cost_usd": sum(r["cost_usd"] for r in rs),
            "unverifiable_total": unverifiable_total,
        })

    # regressions computed by render_scorecard against prior trends line, not here.
    return {
        "schema_version": 1,
        "week_of": week_of.isoformat(),
        "commit_sha": commit_sha,
        "forge_version": forge_version,
        "cells": cells,
        "hook_failures_total": hook_failures_total,
        "regressions": [],
    }


def append_trends(trends_path: Path, line: dict[str, Any]) -> None:
    """Append one JSON line to trends.jsonl (create if missing)."""
    trends_path.parent.mkdir(parents=True, exist_ok=True)
    with trends_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(line, sort_keys=True) + "\n")


def count_hook_failures(artifacts_root: Path) -> int:
    total = 0
    for log in artifacts_root.rglob(".hook-failures.jsonl"):
        total += sum(1 for line in log.read_text(encoding="utf-8").splitlines() if line.strip())
    return total
