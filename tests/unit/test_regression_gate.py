"""Gate: solve-rate drop ≥10pp in any (bucket, model) triggers exit 1."""

from __future__ import annotations

from tests.evals.benchmark.gate import evaluate_gate


def _trends_line(sonnet_s: float, sonnet_m: float = 0.8, sonnet_l: float = 0.5) -> dict:
    return {
        "cells": [
            {
                "os": "ubuntu-latest",
                "model": "claude-sonnet-4-6",
                "entries_total": 10,
                "entries_solved": int(sonnet_s * 10),
                "solve_rate_overall": sonnet_s,
                "solve_rate_by_complexity": {"S": sonnet_s, "M": sonnet_m, "L": sonnet_l},
                "entries_timeout": 0,
                "entries_docker_skipped": 0,
                "median_cost_per_solve_usd": 0.4,
                "total_cost_usd": 4.0,
            }
        ]
    }


def _baseline(overall: float = 0.9, s: float = 0.9, m: float = 0.8, l_: float = 0.5) -> dict:
    return {
        "baselines": {"claude-sonnet-4-6": {"S": s, "M": m, "L": l_, "overall": overall}},
        "regression_threshold_pp": 10,
    }


def test_no_regression_passes() -> None:
    r = evaluate_gate(current=_trends_line(0.9), baseline=_baseline(0.9))
    assert r.passed is True
    assert not r.findings


def test_10pp_drop_fails() -> None:
    r = evaluate_gate(current=_trends_line(0.7), baseline=_baseline(0.9, s=0.9))
    assert r.passed is False
    assert any(f.severity == "CRITICAL" and f.category == "BENCH-REGRESSION" for f in r.findings)


def test_5pp_drop_warns_but_passes() -> None:
    r = evaluate_gate(current=_trends_line(0.84), baseline=_baseline(0.9, s=0.9))
    assert r.passed is True
    assert any(f.severity == "WARNING" and f.category == "BENCH-REGRESSION" for f in r.findings)


def test_no_baseline_is_pass_warning() -> None:
    r = evaluate_gate(current=_trends_line(0.5), baseline=None)
    assert r.passed is True
    assert any(f.severity == "WARNING" for f in r.findings)


def test_baseline_incomplete_bucket() -> None:
    """A baseline missing one bucket emits BENCH-BASELINE-INCOMPLETE WARNING, no crash."""
    # Strip the "M" bucket from the model's baseline.
    base = _baseline(0.9)
    del base["baselines"]["claude-sonnet-4-6"]["M"]
    r = evaluate_gate(current=_trends_line(0.9), baseline=base)
    assert r.passed is True
    assert any(
        f.severity == "WARNING" and f.category == "BENCH-BASELINE-INCOMPLETE" for f in r.findings
    )


def test_mutation_manual_baseline_bump() -> None:
    """AC-809 mutation: bump baseline +15pp; current line that was fine now fails."""
    current = _trends_line(0.8)  # 80%
    original = _baseline(0.82)  # baseline was 82%
    mutated = _baseline(0.97)  # +15pp mutation
    assert evaluate_gate(current=current, baseline=original).passed
    assert not evaluate_gate(current=current, baseline=mutated).passed
