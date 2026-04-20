#!/usr/bin/env python3
"""Speculation dispatch helper (Phase 12)."""
from __future__ import annotations

import argparse
import json
import re
import sys
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

    args = parser.parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
