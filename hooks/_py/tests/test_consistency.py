"""Unit tests for hooks/_py/consistency.py."""
from __future__ import annotations

import asyncio
import hashlib
import json
from pathlib import Path
from typing import Any

import pytest

from hooks._py import consistency


def _key(decision: str, mode: str, prompt: str, n: int, tier: str) -> str:
    raw = f"{decision}\0{mode}\0{prompt}\0{n}\0{tier}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def test_cache_key_includes_state_mode():
    k1 = consistency.cache_key("shaper_intent", "standard", "p", 3, "fast")
    k2 = consistency.cache_key("shaper_intent", "bugfix", "p", 3, "fast")
    assert k1 != k2, "state.mode MUST be part of the cache key"
    assert k1 == _key("shaper_intent", "standard", "p", 3, "fast")


def test_aggregate_simple_majority_returns_mean_confidence():
    samples = [("GO", 0.90), ("GO", 0.80), ("REVISE", 0.60)]
    result = consistency.aggregate(samples, min_consensus_confidence=0.5)
    assert result.label == "GO"
    assert result.confidence == pytest.approx(0.85, rel=1e-6)
    assert result.low_consensus is False


def test_aggregate_tie_uses_confidence_weighted_sum():
    # 2 vs 2 tie; REVISE total 0.9+0.1=1.0, GO total 0.4+0.5=0.9; REVISE wins.
    samples = [("GO", 0.4), ("GO", 0.5), ("REVISE", 0.9), ("REVISE", 0.1)]
    result = consistency.aggregate(samples, min_consensus_confidence=0.5)
    assert result.label == "REVISE"
    assert result.confidence == pytest.approx(0.5, rel=1e-6)


def test_aggregate_perfect_tie_falls_back_to_highest_single():
    # 1 vs 1 with equal sums (0.7 == 0.7) — fall back to highest single.
    samples = [("GO", 0.7), ("REVISE", 0.7)]
    result = consistency.aggregate(samples, min_consensus_confidence=0.5)
    # Ordering is deterministic on highest-single; both are equal, so the
    # helper must return the one seen first. Document that behavior.
    assert result.label in {"GO", "REVISE"}
    assert result.confidence == pytest.approx(0.7, rel=1e-6)


def test_aggregate_low_consensus_flagged():
    samples = [("GO", 0.4), ("GO", 0.3), ("REVISE", 0.2)]
    result = consistency.aggregate(samples, min_consensus_confidence=0.5)
    assert result.label == "GO"
    assert result.low_consensus is True


def test_aggregate_raises_when_too_few_samples_survive():
    # Only 1 survivor out of N=3 — below ceil(3/2)=2.
    with pytest.raises(consistency.ConsistencyError):
        consistency.aggregate_or_raise(
            samples=[("GO", 0.9)],
            n_expected=3,
            min_consensus_confidence=0.5,
        )


def test_cache_write_and_read_roundtrip(tmp_path: Path):
    cache = tmp_path / "consistency-cache.jsonl"
    key = consistency.cache_key("shaper_intent", "standard", "hello", 3, "fast")
    vr = consistency.VoteResult(
        label="bugfix",
        confidence=0.87,
        samples=[("bugfix", 0.9), ("bugfix", 0.85), ("bugfix", 0.86)],
        cache_hit=False,
        low_consensus=False,
    )
    consistency.cache_append(cache, key=key, decision="shaper_intent",
                             mode="standard", n=3, tier="fast", result=vr)
    got = consistency.cache_lookup(cache, key)
    assert got is not None
    assert got.label == "bugfix"
    assert got.confidence == pytest.approx(0.87, rel=1e-6)
    assert got.cache_hit is True


def test_cache_miss_returns_none(tmp_path: Path):
    cache = tmp_path / "consistency-cache.jsonl"
    cache.write_text("")  # empty file
    got = consistency.cache_lookup(cache, "nonexistent-key")
    assert got is None


def test_schema_violation_retried_once_then_dropped():
    # Mock sampler yields two valid + one junk; after retry the junk becomes valid.
    events: list[str] = []

    async def fake_sampler(prompt: str, labels: list[str], tier: str, seed: int) -> dict[str, Any]:
        events.append(f"{seed}")
        if seed == 2:
            # First call: schema violation (missing 'label'); retry yields valid.
            if events.count("2") == 1:
                return {"confidence": 0.5}
            return {"label": "GO", "confidence": 0.5}
        return {"label": "GO", "confidence": 0.9}

    samples = asyncio.run(consistency._collect_samples(
        prompt="x", labels=["GO", "REVISE", "NO-GO"], tier="fast", n=3,
        sampler=fake_sampler,
    ))
    assert len(samples) == 3
    assert all(s[0] in {"GO", "REVISE", "NO-GO"} for s in samples)


def test_schema_violation_twice_drops_sample():
    async def fake_sampler(prompt: str, labels: list[str], tier: str, seed: int) -> dict[str, Any]:
        if seed == 2:
            return {"confidence": 0.5}  # always malformed
        return {"label": "GO", "confidence": 0.9}

    samples = asyncio.run(consistency._collect_samples(
        prompt="x", labels=["GO", "REVISE", "NO-GO"], tier="fast", n=3,
        sampler=fake_sampler,
    ))
    assert len(samples) == 2  # one dropped after retry
