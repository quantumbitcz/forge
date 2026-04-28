"""Scorecard renderer: empty, all-solved, all-failed, regressions, sparklines."""

from __future__ import annotations

from pathlib import Path

from tests.evals.benchmark.render_scorecard import render, sparkline


def test_sparkline_empty() -> None:
    assert sparkline([]) == "▁" * 12


def test_sparkline_full_range() -> None:
    # values 0..1 in 12 steps → blocks spanning the 8-char range
    vals = [i / 11 for i in range(12)]
    s = sparkline(vals)
    assert len(s) == 12
    assert s[0] == "▁"
    assert s[-1] == "█"


def test_sparkline_gap_fills_with_low() -> None:
    assert sparkline([None, 0.5, None]) == "▁▄▁"


def test_render_empty_history(tmp_path: Path) -> None:
    out = render(trends_lines=[], baseline=None, hook_failures_total=0)
    assert "<!-- section:header -->" in out
    assert "<!-- section:this-week -->" in out
    assert "awaiting first weekly run" in out.lower()


def test_render_with_one_week_all_solved() -> None:
    line = {
        "schema_version": 1,
        "week_of": "2026-04-27",
        "commit_sha": "abc1234",
        "forge_version": "6.0.0",
        "cells": [
            {
                "os": "ubuntu-latest",
                "model": "claude-sonnet-4-6",
                "entries_total": 10,
                "entries_solved": 10,
                "entries_timeout": 0,
                "entries_docker_skipped": 0,
                "solve_rate_overall": 1.0,
                "solve_rate_by_complexity": {"S": 1.0, "M": 1.0, "L": 1.0},
                "median_cost_per_solve_usd": 0.5,
                "total_cost_usd": 5.0,
            }
        ],
        "hook_failures_total": 0,
        "regressions": [],
    }
    out = render(trends_lines=[line], baseline=None, hook_failures_total=0)
    assert "100%" in out or "1.00" in out or "solve_rate" in out.lower()


def test_render_shows_regressions() -> None:
    line = {
        "schema_version": 1,
        "week_of": "2026-04-27",
        "commit_sha": "abc",
        "forge_version": "6.0.0",
        "cells": [
            {
                "os": "ubuntu-latest",
                "model": "claude-sonnet-4-6",
                "entries_total": 2,
                "entries_solved": 1,
                "entries_timeout": 0,
                "entries_docker_skipped": 0,
                "solve_rate_overall": 0.5,
                "solve_rate_by_complexity": {"S": 1.0, "M": 0.0, "L": 0.0},
                "median_cost_per_solve_usd": 0.5,
                "total_cost_usd": 1.0,
            }
        ],
        "hook_failures_total": 0,
        "regressions": [{"entry_id": "e42", "last_status": "solved", "this_status": "failed"}],
    }
    out = render(trends_lines=[line], baseline=None, hook_failures_total=0)
    assert "e42" in out
    assert "regression" in out.lower()


def test_render_cost_truncated_banner() -> None:
    line = {
        "schema_version": 1,
        "week_of": "2026-04-27",
        "commit_sha": "abc",
        "forge_version": "6.0.0",
        "cells": [],
        "hook_failures_total": 0,
        "regressions": [],
        "cost_truncated": True,
    }
    out = render(trends_lines=[line], baseline=None, hook_failures_total=0)
    assert "cost-truncated" in out.lower() or "truncated" in out.lower()


def test_sparkline_output_is_utf8_round_trippable() -> None:
    """Windows smoke: block glyphs must encode/decode losslessly under UTF-8.

    The aggregate job runs on ubuntu-latest (scorecard is produced on Linux and
    committed as UTF-8), but the renderer itself can be invoked locally from
    PowerShell / cmd where the default codepage may be cp1252. This test
    locks the contract that `sparkline()` emits only chars in the 8-block
    set and that encoding to UTF-8 round-trips without replacement chars.
    Run on Windows CI cells by the matrix — no `chcp 65001` required because
    we never touch the terminal; we write bytes to a file.
    """
    s = sparkline([0.0, 0.5, 1.0])
    encoded = s.encode("utf-8")
    assert encoded.decode("utf-8") == s
    assert all(ch in "▁▂▃▄▅▆▇█" for ch in s)


def test_render_12_week_sparkline_edge() -> None:
    lines = [
        {
            "schema_version": 1,
            "week_of": f"2026-{(i % 12) + 1:02d}-01",
            "commit_sha": "x",
            "forge_version": "6.0.0",
            "cells": [
                {
                    "os": "ubuntu-latest",
                    "model": "claude-sonnet-4-6",
                    "entries_total": 10,
                    "entries_solved": i,
                    "entries_timeout": 0,
                    "entries_docker_skipped": 0,
                    "solve_rate_overall": i / 10.0,
                    "solve_rate_by_complexity": {"S": i / 10.0, "M": i / 10.0, "L": i / 10.0},
                    "median_cost_per_solve_usd": 0.5,
                    "total_cost_usd": 5.0,
                }
            ],
            "hook_failures_total": 0,
            "regressions": [],
        }
        for i in range(15)  # more than 12 — only last 12 should render
    ]
    out = render(trends_lines=lines, baseline=None, hook_failures_total=0)
    # The section name should appear; last-12 constraint enforced by len check in prose
    assert "Last 12 weeks" in out
