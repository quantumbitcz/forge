"""Solve predicate: verdict ∈ {SHIP, CONCERNS} ∧ partial_ac_pct ≥ 0.9 ∧ critical_findings == 0."""
from __future__ import annotations
import pytest
from tests.evals.benchmark.scoring import solved, SolveInputs


@pytest.mark.parametrize("verdict,ac_pct,criticals,expected", [
    ("SHIP", 1.0, 0, True),
    ("SHIP", 0.9, 0, True),
    ("CONCERNS", 0.9, 0, True),
    ("CONCERNS", 1.0, 0, True),
    ("SHIP", 0.89, 0, False),     # below 0.9 threshold
    ("SHIP", 1.0, 1, False),      # critical present
    ("FAIL", 1.0, 0, False),      # verdict fail
    ("ERROR", 1.0, 0, False),     # verdict error
    ("CONCERNS", 0.89999, 0, False),  # floating boundary just below
    ("CONCERNS", 0.9, 1, False),  # both AC OK and critical present
])
def test_solved(verdict: str, ac_pct: float, criticals: int, expected: bool) -> None:
    assert solved(SolveInputs(
        pipeline_verdict=verdict,
        partial_ac_pct=ac_pct,
        critical_findings=criticals,
    )) is expected


def test_unverifiable_counts_against_ac_pct() -> None:
    """AC breakdown: 3 PASS + 1 UNVERIFIABLE = 0.75 (unverifiable counted as failed)."""
    from tests.evals.benchmark.scoring import compute_partial_ac_pct
    assert compute_partial_ac_pct({"A": "PASS", "B": "PASS", "C": "PASS", "D": "UNVERIFIABLE"}) == pytest.approx(0.75)
    assert compute_partial_ac_pct({}) == 0.0
    assert compute_partial_ac_pct({"A": "PASS"}) == 1.0
