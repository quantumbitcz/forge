"""Self-consistency voting dispatch helper.

Referenced by shared/consistency/voting.md. Do NOT duplicate the protocol
here — keep the contract in voting.md and the code in this file.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import math
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Awaitable, Callable, Iterable

# Sampler signature: (prompt, labels, tier, seed) -> {"label": str, "confidence": float}
Sampler = Callable[[str, list[str], str, int], Awaitable[dict[str, Any]]]


class ConsistencyError(RuntimeError):
    """Raised when too few samples survive parsing to aggregate safely."""


@dataclass(frozen=True)
class VoteResult:
    label: str
    confidence: float
    samples: list[tuple[str, float]]
    cache_hit: bool
    low_consensus: bool


# ---------- Cache key ----------

def cache_key(decision_point: str, state_mode: str, prompt: str,
              n: int, tier: str) -> str:
    """SHA256 of (decision || mode || prompt || n || tier), NUL-separated.

    state_mode is REQUIRED — see shared/consistency/voting.md §3.1.
    """
    raw = f"{decision_point}\0{state_mode}\0{prompt}\0{n}\0{tier}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


# ---------- Cache read/write ----------

def cache_lookup(path: Path, key: str) -> VoteResult | None:
    """Linear scan of JSONL; last hit wins (append-only semantics)."""
    if not path.exists():
        return None
    found: dict[str, Any] | None = None
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("key") == key:
                found = rec
    if found is None:
        return None
    r = found["result"]
    return VoteResult(
        label=r["label"],
        confidence=float(r["confidence"]),
        samples=[(s[0], float(s[1])) for s in r.get("samples", [])],
        cache_hit=True,
        low_consensus=bool(r.get("low_consensus", False)),
    )


def cache_append(path: Path, *, key: str, decision: str, mode: str,
                 n: int, tier: str, result: VoteResult) -> None:
    """Atomic append-one-line to JSONL cache.

    Uses POSIX O_APPEND semantics: on most filesystems a single write(2) of a
    line <= PIPE_BUF is atomic with respect to concurrent writers. We enforce
    "one line per write" by building the full record first and writing once.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "key": key,
        "decision": decision,
        "mode": mode,
        "n": n,
        "tier": tier,
        "result": {
            "label": result.label,
            "confidence": result.confidence,
            "samples": [list(s) for s in result.samples],
            "low_consensus": result.low_consensus,
        },
    }
    line = json.dumps(record, separators=(",", ":")) + "\n"
    with path.open("a", encoding="utf-8") as fh:
        fh.write(line)


# ---------- Aggregation ----------

def aggregate(samples: list[tuple[str, float]],
              *, min_consensus_confidence: float) -> VoteResult:
    """Majority → confidence-weighted-sum tiebreak → highest-single fallback.

    Matches shared/consistency/voting.md §2.
    """
    if not samples:
        raise ConsistencyError("aggregate called with zero samples")

    # Group by label, preserving first-seen order for deterministic ties.
    groups: dict[str, list[float]] = {}
    order: list[str] = []
    for label, conf in samples:
        if label not in groups:
            groups[label] = []
            order.append(label)
        groups[label].append(float(conf))

    counts = {lab: len(confs) for lab, confs in groups.items()}
    max_count = max(counts.values())
    top_labels = [lab for lab in order if counts[lab] == max_count]

    if len(top_labels) == 1:
        winner = top_labels[0]
        mean_conf = sum(groups[winner]) / len(groups[winner])
        return VoteResult(
            label=winner,
            confidence=mean_conf,
            samples=samples,
            cache_hit=False,
            low_consensus=mean_conf < min_consensus_confidence,
        )

    # Tie on count — sum confidences per tied group.
    sums = {lab: sum(groups[lab]) for lab in top_labels}
    max_sum = max(sums.values())
    top_by_sum = [lab for lab in top_labels if sums[lab] == max_sum]

    if len(top_by_sum) == 1:
        winner = top_by_sum[0]
        mean_conf = sum(groups[winner]) / len(groups[winner])
        return VoteResult(
            label=winner,
            confidence=mean_conf,
            samples=samples,
            cache_hit=False,
            low_consensus=mean_conf < min_consensus_confidence,
        )

    # Final fallback: single highest confidence, first-seen on tie.
    best_idx = 0
    best_conf = samples[0][1]
    for i, (_, conf) in enumerate(samples):
        if conf > best_conf:
            best_idx = i
            best_conf = conf
    winner_label, winner_conf = samples[best_idx]
    return VoteResult(
        label=winner_label,
        confidence=winner_conf,
        samples=samples,
        cache_hit=False,
        low_consensus=winner_conf < min_consensus_confidence,
    )


def aggregate_or_raise(samples: list[tuple[str, float]], *,
                       n_expected: int,
                       min_consensus_confidence: float) -> VoteResult:
    """Raise ConsistencyError if fewer than ceil(N/2) samples survive."""
    threshold = math.ceil(n_expected / 2)
    if len(samples) < threshold:
        raise ConsistencyError(
            f"only {len(samples)}/{n_expected} samples survived (need >= {threshold})"
        )
    return aggregate(samples, min_consensus_confidence=min_consensus_confidence)


# ---------- Sample collection ----------

def _valid(rec: Any, labels: list[str]) -> bool:
    if not isinstance(rec, dict):
        return False
    lbl = rec.get("label")
    conf = rec.get("confidence")
    if lbl not in labels:
        return False
    try:
        f = float(conf)
    except (TypeError, ValueError):
        return False
    return 0.0 <= f <= 1.0


async def _one_sample(sampler: Sampler, prompt: str, labels: list[str],
                      tier: str, seed: int) -> tuple[str, float] | None:
    """Call sampler; retry once on schema violation; drop on second failure."""
    for attempt in range(2):
        try:
            rec = await sampler(prompt, labels, tier, seed)
        except Exception:
            continue
        if _valid(rec, labels):
            return (rec["label"], float(rec["confidence"]))
    return None


async def _collect_samples(*, prompt: str, labels: list[str], tier: str,
                           n: int, sampler: Sampler) -> list[tuple[str, float]]:
    tasks = [_one_sample(sampler, prompt, labels, tier, seed=i) for i in range(n)]
    results = await asyncio.gather(*tasks)
    return [r for r in results if r is not None]


# ---------- Public entry point ----------

async def vote_async(*, decision_point: str, prompt: str, labels: list[str],
                     state_mode: str, n: int = 3, tier: str = "fast",
                     cache_enabled: bool = True,
                     min_consensus_confidence: float = 0.5,
                     cache_path: Path | None = None,
                     sampler: Sampler | None = None,
                     state_incr: Callable[[str, str], None] | None = None,
                     ) -> VoteResult:
    """Main entry. Synchronous callers use `vote(...)`."""
    if sampler is None:
        raise ValueError("sampler must be provided")
    if cache_path is None:
        cache_path = Path(".forge") / "consistency-cache.jsonl"

    key = cache_key(decision_point, state_mode, prompt, n, tier)

    if cache_enabled:
        hit = cache_lookup(cache_path, key)
        if hit is not None:
            if state_incr is not None:
                state_incr("consistency_cache_hits", decision_point)
            return hit

    raw = await _collect_samples(prompt=prompt, labels=labels, tier=tier,
                                 n=n, sampler=sampler)
    result = aggregate_or_raise(
        raw, n_expected=n, min_consensus_confidence=min_consensus_confidence,
    )

    if cache_enabled:
        cache_append(cache_path, key=key, decision=decision_point,
                     mode=state_mode, n=n, tier=tier, result=result)
    return result


def vote(**kwargs) -> VoteResult:
    """Synchronous wrapper. Agents call this one."""
    return asyncio.run(vote_async(**kwargs))
