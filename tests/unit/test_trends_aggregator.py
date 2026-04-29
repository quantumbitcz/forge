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


def test_regression_detection(tmp_path: Path) -> None:
    """Cell solve-rate drop ≥5pp vs prior week appears in `regressions`."""
    # Week 1: 1/1 solved (100%) for cell (ubuntu-latest, claude-sonnet-4-6).
    _seed(tmp_path, "e1", "ubuntu-latest", "claude-sonnet-4-6", True, 0.5, "S")
    week1 = aggregate_week(
        results_root=tmp_path,
        week_of=date(2026, 4, 27),
        commit_sha="w1",
        forge_version="6.0.0",
        hook_failures_total=0,
    )
    assert week1["regressions"] == []

    # Week 2: same cell flips to 0/1 (0%) — 100pp drop.
    week2_dir = tmp_path / "2026-05-04"
    week2_dir.mkdir()
    doc = {
        "schema_version": 1,
        "entry_id": "e1",
        "run_date": "2026-05-04",
        "os": "ubuntu-latest",
        "model": "claude-sonnet-4-6",
        "complexity": "S",
        "started_at": "2026-05-04T06:00:00Z",
        "ended_at": "2026-05-04T06:10:00Z",
        "duration_s": 600,
        "solved": False,
        "partial_ac_pct": 0.0,
        "ac_breakdown": {"AC-B001": "FAIL"},
        "unverifiable_count": 0,
        "cost_usd": 1.0,
        "pipeline_verdict": "FAIL",
        "score": 30,
        "convergence_iterations": 1,
        "critical_findings": 1,
        "warning_findings": 0,
        "timeout": False,
        "must_not_touch_violations": [],
        "touched_files_actual": [],
        "hook_failures_count": 0,
        "error": None,
    }
    (week2_dir / "e1.ubuntu-latest.claude-sonnet-4-6.json").write_text(json.dumps(doc))

    week2 = aggregate_week(
        results_root=tmp_path,
        week_of=date(2026, 5, 4),
        commit_sha="w2",
        forge_version="6.0.0",
        hook_failures_total=0,
        prior_trends_line=week1,
    )
    regs = week2["regressions"]
    assert len(regs) == 1
    r = regs[0]
    assert r["os"] == "ubuntu-latest"
    assert r["model"] == "claude-sonnet-4-6"
    assert r["prev_solve_rate"] == 1.0
    assert r["curr_solve_rate"] == 0.0
    assert r["delta_pp"] == -100.0
    assert r["severity"] == "CRITICAL"


def test_cost_truncated_flag(tmp_path: Path) -> None:
    """`cost_truncated=True` is reflected in the returned dict."""
    _seed(tmp_path, "e1", "ubuntu-latest", "claude-sonnet-4-6", True, 0.5, "S")
    line = aggregate_week(
        results_root=tmp_path,
        week_of=date(2026, 4, 27),
        commit_sha="x",
        forge_version="6.0.0",
        hook_failures_total=0,
        cost_truncated=True,
    )
    assert line["cost_truncated"] is True


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
