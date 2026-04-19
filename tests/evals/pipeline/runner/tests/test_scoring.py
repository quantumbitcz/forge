"""Tests for composite scoring math."""
from __future__ import annotations

import pytest

from tests.evals.pipeline.runner.scoring import (
    clamp01,
    composite_score,
    elapsed_adherence,
    jaccard_overlap,
    token_adherence,
)


def test_clamp01_bounds():
    assert clamp01(-0.5) == 0.0
    assert clamp01(0.0) == 0.0
    assert clamp01(0.5) == 0.5
    assert clamp01(1.0) == 1.0
    assert clamp01(2.5) == 1.0


def test_token_adherence_exact_budget_is_one():
    assert token_adherence(actual=150_000, budget=150_000) == pytest.approx(1.0)


def test_token_adherence_half_budget_is_capped_at_one():
    # Formula: clamp01(2 - actual/budget). Half-budget → 2 - 0.5 = 1.5 → clamped to 1.0.
    assert token_adherence(actual=75_000, budget=150_000) == 1.0


def test_token_adherence_double_budget_is_zero():
    assert token_adherence(actual=300_000, budget=150_000) == 0.0


def test_token_adherence_150pct_budget_is_half():
    # 2 - 1.5 = 0.5
    assert token_adherence(actual=225_000, budget=150_000) == pytest.approx(0.5)


def test_elapsed_adherence_mirrors_token_formula():
    assert elapsed_adherence(actual=600, budget=600) == pytest.approx(1.0)
    assert elapsed_adherence(actual=1200, budget=600) == 0.0
    assert elapsed_adherence(actual=300, budget=600) == 1.0


def test_jaccard_overlap_identical_sets_is_one():
    assert jaccard_overlap(["a", "b"], ["a", "b"]) == pytest.approx(1.0)


def test_jaccard_overlap_disjoint_sets_is_zero():
    assert jaccard_overlap(["a", "b"], ["c", "d"]) == 0.0


def test_jaccard_overlap_empty_both_is_one():
    # Defined: empty ∩ empty / empty ∪ empty → conventionally 1.0 (perfect agreement on "nothing").
    assert jaccard_overlap([], []) == 1.0


def test_jaccard_overlap_partial_overlap():
    # {a,b,c} vs {b,c,d} → intersection 2, union 4 → 0.5
    assert jaccard_overlap(["a", "b", "c"], ["b", "c", "d"]) == pytest.approx(0.5)


def test_composite_score_all_perfect():
    c = composite_score(pipeline_score=100.0, token_adh=1.0, elapsed_adh=1.0)
    assert c == pytest.approx(100.0)


def test_composite_score_weighting_is_50_25_25():
    # pipeline=80, token=1.0, elapsed=1.0  →  100*(0.5*0.8 + 0.25 + 0.25) = 90
    c = composite_score(pipeline_score=80.0, token_adh=1.0, elapsed_adh=1.0)
    assert c == pytest.approx(90.0)


def test_composite_score_zero_pipeline_still_has_adherence_credit():
    # pipeline=0, token=1.0, elapsed=1.0  →  100*(0 + 0.25 + 0.25) = 50
    c = composite_score(pipeline_score=0.0, token_adh=1.0, elapsed_adh=1.0)
    assert c == pytest.approx(50.0)


def test_composite_score_zero_budget_credit():
    # pipeline=100, token=0, elapsed=0  →  100*(0.5 + 0 + 0) = 50
    c = composite_score(pipeline_score=100.0, token_adh=0.0, elapsed_adh=0.0)
    assert c == pytest.approx(50.0)
