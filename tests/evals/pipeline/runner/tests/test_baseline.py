"""Tests for baseline fetch and regression-gate diff."""
from __future__ import annotations

from tests.evals.pipeline.runner.baseline import (
    BaselineUnavailable,
    compute_gate,
)
from tests.evals.pipeline.runner.schema import Finding


def _mkresults(composites: list[float]) -> list[dict]:
    return [
        {
            "scenario_id": f"s{i:02d}",
            "composite": c,
        }
        for i, c in enumerate(composites)
    ]


def test_compute_gate_passes_when_delta_within_tolerance():
    baseline = _mkresults([80, 85, 90])
    current = _mkresults([79, 83, 89])   # mean: 83.67 vs 85.0 → -1.33
    decision = compute_gate(current=current, baseline=baseline, tolerance=3.0)
    assert decision.passed is True
    assert decision.delta < 0
    assert decision.finding is None


def test_compute_gate_fails_when_delta_exceeds_tolerance():
    baseline = _mkresults([80, 85, 90])    # mean 85.0
    current = _mkresults([70, 75, 80])     # mean 75.0 → delta -10
    decision = compute_gate(current=current, baseline=baseline, tolerance=3.0)
    assert decision.passed is False
    assert decision.delta == -10.0
    assert decision.finding is not None
    assert decision.finding.category == "EVAL-REGRESSION"
    assert decision.finding.severity == "CRITICAL"


def test_compute_gate_passes_when_current_better_than_baseline():
    baseline = _mkresults([80, 80, 80])
    current = _mkresults([90, 90, 90])
    decision = compute_gate(current=current, baseline=baseline, tolerance=3.0)
    assert decision.passed is True
    assert decision.delta == 10.0


def test_compute_gate_emits_unavailable_when_baseline_missing():
    current = _mkresults([80])
    decision = compute_gate(current=current, baseline=None, tolerance=3.0)
    assert decision.passed is True        # skip-gate behavior per plan §Review C3
    assert decision.finding is not None
    assert decision.finding.category == "EVAL-BASELINE-UNAVAILABLE"
    assert decision.finding.severity == "WARNING"


def test_baseline_unavailable_is_exception_subclass():
    assert issubclass(BaselineUnavailable, Exception)


def test_finding_from_gate_serializes():
    f = Finding(category="EVAL-REGRESSION", severity="CRITICAL", message="drop 10")
    d = f.model_dump()
    assert d["category"] == "EVAL-REGRESSION"
