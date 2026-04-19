"""Composite score math for the pipeline eval harness.

Formula (per spec §6):

    token_adherence    = clamp01(2 - actual_tokens / expected_token_budget)
    elapsed_adherence  = clamp01(2 - actual_elapsed / expected_elapsed_budget)
    composite          = 100 * (
                           0.50 * (pipeline_score / 100)
                         + 0.25 * token_adherence
                         + 0.25 * elapsed_adherence
                       )

Overlap (Jaccard, reporting-only) is in a separate helper.
"""
from __future__ import annotations

from typing import Iterable


def clamp01(value: float) -> float:
    """Clamp to [0.0, 1.0]."""
    if value < 0.0:
        return 0.0
    if value > 1.0:
        return 1.0
    return float(value)


def token_adherence(actual: int, budget: int) -> float:
    """Linear adherence: full credit at ≤50% of budget, zero credit at ≥200%.

    Raises ValueError on non-positive budget (scenario author bug — fail loud).
    """
    if budget <= 0:
        raise ValueError(f"token budget must be positive, got {budget}")
    return clamp01(2.0 - (actual / budget))


def elapsed_adherence(actual: int, budget: int) -> float:
    """Same shape as token_adherence, for wall-clock seconds."""
    if budget <= 0:
        raise ValueError(f"elapsed budget must be positive, got {budget}")
    return clamp01(2.0 - (actual / budget))


def jaccard_overlap(expected: Iterable[str], actual: Iterable[str]) -> float:
    """Jaccard similarity of two string sets. Empty vs empty defined as 1.0."""
    a, b = set(expected), set(actual)
    if not a and not b:
        return 1.0
    union = a | b
    if not union:
        return 1.0
    return len(a & b) / len(union)


def composite_score(pipeline_score: float, token_adh: float, elapsed_adh: float) -> float:
    """Weighted composite: 0.5 × pipeline + 0.25 × token + 0.25 × elapsed, scaled to 100."""
    return 100.0 * (
        0.50 * (pipeline_score / 100.0)
        + 0.25 * token_adh
        + 0.25 * elapsed_adh
    )
