#!/usr/bin/env python3
"""Speculation dispatch helper (Phase 12)."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from itertools import combinations
from typing import Any

KEYWORD_PATTERN = re.compile(
    r"\b(either|or|could|maybe|consider|multiple approaches)\b|"
    r"\b[A-Za-z]+/[A-Za-z]+\b",
    re.IGNORECASE,
)

MIN_REQUIREMENT_WORDS = 15
PLAN_CACHE_SKIP_THRESHOLD = 0.60
PLAN_CACHE_MARGINAL_LOW = 0.40
PLAN_CACHE_MARGINAL_HIGH = 0.59
SHAPER_DELTA_MAX = 10
DOMAIN_DELTA_MAX = 0.15

COLD_START_DEFAULT = 4500
WINDOW = 10

STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "for", "with",
    "is", "are", "be", "as", "by", "at", "this", "that", "it", "from",
}

VERDICT_BONUSES = {"GO": 0, "REVISE": -15}


def detect_ambiguity(
    requirement: str,
    confidence: str,
    shaper_alternatives: int,
    shaper_delta: int,
    plan_cache_sim: float,
    domain_count: int = 0,
    domain_delta: float = 1.0,
) -> dict[str, Any]:
    """Return {triggered, reasons, confidence}. Shaper signal is elevated."""
    reasons: list[str] = []

    if confidence != "MEDIUM":
        return {"triggered": False, "reasons": [], "confidence": confidence}

    if plan_cache_sim >= PLAN_CACHE_SKIP_THRESHOLD:
        return {
            "triggered": False,
            "reasons": ["plan_cache_hit>=0.60"],
            "confidence": confidence,
        }

    if len(requirement.split()) < MIN_REQUIREMENT_WORDS:
        return {
            "triggered": False,
            "reasons": ["requirement_too_short"],
            "confidence": confidence,
        }

    shaper_ok = shaper_alternatives >= 2 and shaper_delta <= SHAPER_DELTA_MAX
    if shaper_ok:
        reasons.append("shaper_alternatives>=2")

    if KEYWORD_PATTERN.search(requirement):
        reasons.append("keyword_hit")

    if domain_count >= 2 and domain_delta <= DOMAIN_DELTA_MAX:
        reasons.append("multi_domain_hit")

    if PLAN_CACHE_MARGINAL_LOW <= plan_cache_sim <= PLAN_CACHE_MARGINAL_HIGH:
        reasons.append("marginal_cache_hit")

    return {
        "triggered": bool(reasons),
        "reasons": reasons,
        "confidence": confidence,
    }


def derive_seed(run_id: str, candidate_id: str) -> int:
    """Deterministic seed: sha256(run_id + candidate_id) mod 2^31."""
    h = hashlib.sha256(f"{run_id}{candidate_id}".encode()).digest()
    return int.from_bytes(h[:4], "big") % (2 ** 31)


def estimate_cost(
    baseline: int,
    n: int,
    ceiling: float,
    recent_tokens: list[int] | None = None,
    cold_start_default: int = COLD_START_DEFAULT,
) -> dict[str, Any]:
    """estimated = baseline + (mean(recent_tokens[-10:]) or cold_start_default) * n.

    abort = estimated > baseline * ceiling.
    """
    recent_tokens = recent_tokens or []
    window = recent_tokens[-WINDOW:]
    per_candidate = (sum(window) // len(window)) if window else cold_start_default
    estimated = baseline + per_candidate * n
    abort = estimated > int(baseline * ceiling)
    return {
        "estimated": estimated,
        "per_candidate_mean": per_candidate,
        "window_used": len(window),
        "abort": abort,
        "ceiling_tokens": int(baseline * ceiling),
    }


def _cmd_derive_seed(args: argparse.Namespace) -> None:
    sys.stdout.write(str(derive_seed(args.run_id, args.candidate_id)) + "\n")


def _cmd_estimate_cost(args: argparse.Namespace) -> None:
    tokens = (
        [int(x) for x in args.recent_tokens.split(",") if x]
        if args.recent_tokens
        else []
    )
    result = estimate_cost(
        baseline=args.baseline,
        n=args.n,
        ceiling=args.ceiling,
        recent_tokens=tokens,
    )
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")


def _tokens(text: str) -> set[str]:
    """Tokenize to a stopword-filtered set of lowercase alphabetic words (>=2 chars)."""
    return {w.lower() for w in re.findall(r"[A-Za-z]{2,}", text)} - STOPWORDS


def _jaccard(a: set[str], b: set[str]) -> float:
    if not a and not b:
        return 1.0
    union = a | b
    if not union:
        return 1.0
    return len(a & b) / len(union)


def check_diversity(plan_texts: list[str], min_diversity_score: float) -> dict[str, Any]:
    """diversity = 1 - max_pairwise_jaccard; degraded = diversity < threshold."""
    token_sets = [_tokens(p) for p in plan_texts]
    if len(token_sets) < 2:
        return {
            "diversity": 1.0,
            "max_pairwise_overlap": 0.0,
            "degraded": False,
            "threshold": min_diversity_score,
        }

    max_overlap = max(_jaccard(a, b) for a, b in combinations(token_sets, 2))
    diversity = round(1.0 - max_overlap, 4)
    return {
        "diversity": diversity,
        "max_pairwise_overlap": round(max_overlap, 4),
        "degraded": diversity < min_diversity_score,
        "threshold": min_diversity_score,
    }


def _cmd_check_diversity(args: argparse.Namespace) -> None:
    texts: list[str] = []
    for path in args.plan:
        with open(path, encoding="utf-8") as f:
            texts.append(f.read())
    result = check_diversity(texts, args.min_diversity_score)
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")


def _cmd_detect_ambiguity(args: argparse.Namespace) -> None:
    result = detect_ambiguity(
        requirement=args.requirement,
        confidence=args.confidence,
        shaper_alternatives=args.shaper_alternatives,
        shaper_delta=args.shaper_delta,
        plan_cache_sim=args.plan_cache_sim,
        domain_count=args.domain_count,
        domain_delta=args.domain_delta,
    )
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(prog="speculation.py")
    subparsers = parser.add_subparsers(dest="cmd", required=True)

    p_detect = subparsers.add_parser("detect-ambiguity")
    p_detect.add_argument("--requirement", required=True)
    p_detect.add_argument("--confidence", required=True, choices=["HIGH", "MEDIUM", "LOW"])
    p_detect.add_argument("--shaper-alternatives", type=int, default=0)
    p_detect.add_argument("--shaper-delta", type=int, default=0)
    p_detect.add_argument("--plan-cache-sim", type=float, default=0.0)
    p_detect.add_argument("--domain-count", type=int, default=0)
    p_detect.add_argument("--domain-delta", type=float, default=1.0)
    p_detect.set_defaults(func=_cmd_detect_ambiguity)

    p_seed = subparsers.add_parser("derive-seed")
    p_seed.add_argument("--run-id", required=True)
    p_seed.add_argument("--candidate-id", required=True)
    p_seed.set_defaults(func=_cmd_derive_seed)

    p_cost = subparsers.add_parser("estimate-cost")
    p_cost.add_argument("--baseline", type=int, required=True)
    p_cost.add_argument("--n", type=int, required=True)
    p_cost.add_argument("--ceiling", type=float, required=True)
    p_cost.add_argument("--recent-tokens", type=str, default="")
    p_cost.set_defaults(func=_cmd_estimate_cost)

    p_div = subparsers.add_parser("check-diversity")
    p_div.add_argument("--plan", action="append", required=True)
    p_div.add_argument("--min-diversity-score", type=float, required=True)
    p_div.set_defaults(func=_cmd_check_diversity)

    args = parser.parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
