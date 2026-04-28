"""Aggregator: combine per-cell BenchmarkResult files into one trends.jsonl line."""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path

from tests.evals.benchmark.aggregate import aggregate_week


def _seed(
    root: Path, entry_id: str, os: str, model: str, solved: bool, cost: float, complexity: str
) -> None:
    d = root / "2026-04-27"
    d.mkdir(parents=True, exist_ok=True)
    doc = {
        "schema_version": 1,
        "entry_id": entry_id,
        "run_date": "2026-04-27",
        "os": os,
        "model": model,
        "complexity": complexity,
        "started_at": "2026-04-27T06:00:00Z",
        "ended_at": "2026-04-27T06:10:00Z",
        "duration_s": 600,
        "solved": solved,
        "partial_ac_pct": 1.0 if solved else 0.5,
        "ac_breakdown": {"AC-B001": "PASS" if solved else "FAIL"},
        "unverifiable_count": 0,
        "cost_usd": cost,
        "pipeline_verdict": "SHIP" if solved else "FAIL",
        "score": 95 if solved else 40,
        "convergence_iterations": 2,
        "critical_findings": 0 if solved else 2,
        "warning_findings": 0,
        "timeout": False,
        "must_not_touch_violations": [],
        "touched_files_actual": [],
        "hook_failures_count": 0,
        "error": None,
    }
    (d / f"{entry_id}.{os}.{model}.json").write_text(json.dumps(doc))


def test_aggregate_single_week(tmp_path: Path) -> None:
    # two entries on one cell
    _seed(tmp_path, "e1", "ubuntu-latest", "claude-sonnet-4-6", True, 0.5, "S")
    _seed(tmp_path, "e2", "ubuntu-latest", "claude-sonnet-4-6", False, 1.0, "M")
    line = aggregate_week(
        results_root=tmp_path,
        week_of=date(2026, 4, 27),
        commit_sha="abc1234",
        forge_version="6.0.0",
        hook_failures_total=3,
    )
    assert line["schema_version"] == 1
    assert line["hook_failures_total"] == 3
    cell = line["cells"][0]
    assert cell["entries_total"] == 2
    assert cell["entries_solved"] == 1
    assert cell["solve_rate_overall"] == 0.5
    assert cell["median_cost_per_solve_usd"] == 0.5  # only one solved, its cost
    # Bucket-split comes from the real `complexity` field on each result.
    assert cell["solve_rate_by_complexity"] == {"S": 1.0, "M": 0.0}


def test_aggregate_rejects_legacy_missing_complexity(tmp_path: Path) -> None:
    """Results without `complexity` are a hard contract violation (no silent 'S' fallback)."""
    import pytest

    d = tmp_path / "2026-04-27"
    d.mkdir(parents=True)
    (d / "bad.ubuntu-latest.claude-sonnet-4-6.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "entry_id": "bad",
                "solved": True,
                "cost_usd": 0.0,
                "os": "ubuntu-latest",
                "model": "claude-sonnet-4-6",
                "timeout": False,
                # No 'complexity' — aggregator must refuse.
            }
        )
    )
    with pytest.raises(KeyError, match="complexity"):
        aggregate_week(
            results_root=tmp_path,
            week_of=date(2026, 4, 27),
            commit_sha="x",
            forge_version="6.0.0",
            hook_failures_total=0,
        )
