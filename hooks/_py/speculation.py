#!/usr/bin/env python3
"""Speculation dispatch helper."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from itertools import combinations
from pathlib import Path
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
RETENTION_RUNS = 20
SCHEMA_VERSION = "1.0.0"

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


def compute_selection_score(
    validator_score: int,
    verdict: str,
    tokens: int,
    batch_max_tokens: int,
) -> dict[str, Any]:
    """Selection score = validator_score + verdict_bonus + 0.1 * token_efficiency.

    NO-GO candidates are eliminated (selection_score = None).
    """
    if verdict == "NO-GO":
        return {"selection_score": None, "eliminated": True, "verdict": verdict}
    bonus = VERDICT_BONUSES.get(verdict, 0)
    efficiency = 0.0
    if batch_max_tokens > 0:
        efficiency = (batch_max_tokens - tokens) / batch_max_tokens * 100
    score = validator_score + bonus + 0.1 * efficiency
    return {
        "selection_score": round(score, 4),
        "eliminated": False,
        "verdict": verdict,
        "token_efficiency_bonus": round(efficiency, 4),
    }


def pick_winner(
    candidates: list[dict[str, Any]],
    auto_pick_threshold_delta: int,
    mode: str,
) -> dict[str, Any]:
    """Rank scored candidates and pick a winner.

    candidates: [{id, validator_score, verdict, tokens}, ...].
    - All NO-GO -> escalate "all_no_go".
    - Top selection_score < 60 -> escalate "all_below_60".
    - Delta <= threshold and interactive -> needs_confirmation=True.
    - Delta <= threshold and autonomous -> auto-pick top.
    - Otherwise decisive top.
    """
    batch_max = max((c["tokens"] for c in candidates), default=0)

    scored = []
    for c in candidates:
        s = compute_selection_score(
            c["validator_score"], c["verdict"], c["tokens"], batch_max
        )
        scored.append({**c, **s})

    eligible = [c for c in scored if not c["eliminated"]]

    if not eligible:
        return {
            "winner_id": None,
            "needs_confirmation": False,
            "escalate": "all_no_go",
            "runners_up": [c["id"] for c in scored],
            "mode": mode,
        }

    eligible.sort(key=lambda c: c["selection_score"], reverse=True)
    top = eligible[0]

    if top["selection_score"] < 60:
        return {
            "winner_id": None,
            "needs_confirmation": False,
            "escalate": "all_below_60",
            "runners_up": [c["id"] for c in eligible],
            "mode": mode,
        }

    delta = (
        top["selection_score"] - eligible[1]["selection_score"]
        if len(eligible) > 1
        else float("inf")
    )
    tied = delta <= auto_pick_threshold_delta and len(eligible) > 1
    needs_confirmation = tied and mode == "interactive"

    return {
        "winner_id": top["id"],
        "needs_confirmation": needs_confirmation,
        "runners_up": [c["id"] for c in eligible[1:]],
        "top_score": top["selection_score"],
        "delta_to_next": None if delta == float("inf") else round(delta, 4),
        "mode": mode,
        "reasoning": (
            "tie_autonomous_auto_pick"
            if tied and mode == "autonomous"
            else ("tie_interactive_ask_user" if tied else "decisive_top_score")
        ),
    }


def _parse_candidate(spec: str) -> dict[str, Any]:
    """Parse 'id:verdict:validator_score:tokens' into a candidate dict."""
    parts = spec.split(":")
    return {
        "id": parts[0],
        "verdict": parts[1],
        "validator_score": int(parts[2]),
        "tokens": int(parts[3]),
    }


def _cmd_compute_selection(args: argparse.Namespace) -> None:
    result = compute_selection_score(
        args.validator_score, args.verdict, args.tokens, args.batch_max_tokens
    )
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")


def _cmd_pick_winner(args: argparse.Namespace) -> None:
    candidates = [_parse_candidate(c) for c in args.candidate]
    result = pick_winner(candidates, args.auto_pick_threshold_delta, args.mode)
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")


def persist_candidate(forge_dir: str, run_id: str, candidate: dict[str, Any]) -> str:
    """Write candidate JSON under .forge/plans/candidates/{run_id}/cand-{N}.json.

    Maintains .forge/plans/candidates/index.json as an ordered list of
    {run_id, candidate_count, created_at, updated_at} entries. FIFO evicts the
    oldest run directory when more than RETENTION_RUNS runs are indexed.

    Returns the absolute path of the written candidate JSON file.
    """
    base = Path(forge_dir) / "plans" / "candidates"
    run_dir = base / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    candidate.setdefault("schema_version", SCHEMA_VERSION)
    cand_path = run_dir / f"{candidate['candidate_id']}.json"
    cand_path.write_text(json.dumps(candidate, indent=2))

    index_path = base / "index.json"
    index: dict[str, Any] = {"runs": []}
    if index_path.exists():
        try:
            index = json.loads(index_path.read_text())
        except json.JSONDecodeError:
            index = {"runs": []}

    runs: list[dict[str, Any]] = index.get("runs", [])
    existing = next((r for r in runs if r["run_id"] == run_id), None)
    if existing:
        existing["candidate_count"] = existing.get("candidate_count", 0) + 1
        existing["updated_at"] = candidate["created_at"]
    else:
        runs.append(
            {
                "run_id": run_id,
                "candidate_count": 1,
                "created_at": candidate["created_at"],
                "updated_at": candidate["created_at"],
            }
        )

    # FIFO is insertion-order; created_at is informational only. Do not sort,
    # because timestamps may not be zero-padded and lexicographic sort would
    # misorder (e.g. "...:10Z" < "...:1Z"). Append order reflects real FIFO.

    while len(runs) > RETENTION_RUNS:
        evicted = runs.pop(0)
        evicted_dir = base / evicted["run_id"]
        if evicted_dir.exists():
            for f in evicted_dir.iterdir():
                f.unlink()
            evicted_dir.rmdir()

    index["runs"] = runs
    index_path.write_text(json.dumps(index, indent=2))
    return str(cand_path)


def _read_candidate_json(raw: str) -> dict[str, Any]:
    """Accept either a literal JSON string or `@path` to a JSON file."""
    if raw.startswith("@"):
        return json.loads(Path(raw[1:]).read_text())
    return json.loads(raw)


def _cmd_persist_candidate(args: argparse.Namespace) -> None:
    candidate = _read_candidate_json(args.candidate_json)
    path = persist_candidate(args.forge_dir, args.run_id, candidate)
    json.dump({"written": path}, sys.stdout)
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

    p_sel = subparsers.add_parser("compute-selection")
    p_sel.add_argument("--validator-score", type=int, required=True)
    p_sel.add_argument("--verdict", required=True, choices=["GO", "REVISE", "NO-GO"])
    p_sel.add_argument("--tokens", type=int, required=True)
    p_sel.add_argument("--batch-max-tokens", type=int, required=True)
    p_sel.set_defaults(func=_cmd_compute_selection)

    p_pick = subparsers.add_parser("pick-winner")
    p_pick.add_argument("--auto-pick-threshold-delta", type=int, required=True)
    p_pick.add_argument("--mode", required=True, choices=["interactive", "autonomous"])
    p_pick.add_argument(
        "--candidate",
        action="append",
        required=True,
        help="'id:verdict:validator_score:tokens'",
    )
    p_pick.set_defaults(func=_cmd_pick_winner)

    p_persist = subparsers.add_parser("persist-candidate")
    p_persist.add_argument("--forge-dir", required=True)
    p_persist.add_argument("--run-id", required=True)
    p_persist.add_argument(
        "--candidate-json",
        required=True,
        help="JSON literal, or @path for file-based input",
    )
    p_persist.set_defaults(func=_cmd_persist_candidate)

    args = parser.parse_args()
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
