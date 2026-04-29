#!/usr/bin/env python3
"""Convergence Engine Simulator — executable specification.

Python port of convergence-engine-sim.sh. The original required
``bc`` for floating-point math, which isn't available on Windows. This port
removes that dependency and is the new canonical algorithm — convergence-engine.md
is the prose explanation.

Output (one line per cycle):
  cycle=N score=S delta=D smoothed=SM phase=PHASE plateau_count=PC decision=DECISION
"""
from __future__ import annotations

import argparse
import sys


def smoothed_delta(history: list[float]) -> float:
    """4-case smoothed delta from convergence-engine.md.

    <2 scores: 0
    2 scores:  raw delta
    3 scores:  2-point weighted (0.6 / 0.4)
    4+ scores: 3-point weighted (0.5 / 0.3 / 0.2)
    """
    n = len(history)
    if n < 2:
        return 0.0
    if n == 2:
        return history[1] - history[0]
    if n == 3:
        d1 = history[2] - history[1]
        d2 = history[1] - history[0]
        return d1 * 0.6 + d2 * 0.4
    # 4+ scores: use last 4 entries
    d1 = history[-1] - history[-2]
    d2 = history[-2] - history[-3]
    d3 = history[-3] - history[-4]
    return d1 * 0.5 + d2 * 0.3 + d3 * 0.2


def _fmt(num: float) -> str:
    """Match the output style of `bc` — drop trailing .0 from whole numbers."""
    if num == int(num):
        return str(int(num))
    return f"{num:.2f}".rstrip("0").rstrip(".")


def simulate(
    scores: list[float],
    *,
    pass_threshold: int = 80,
    plateau_threshold: int = 2,
    plateau_patience: int = 2,
    oscillation_tolerance: int = 5,
    max_iterations: int = 10,
    target_score: int = 90,  # noqa: ARG001 (kept for parity with bash version)
) -> list[str]:
    """Run the simulation; return one output line per cycle."""
    plateau_count = 0
    history: list[float] = []
    lines: list[str] = []

    for i, score in enumerate(scores):
        cycle = i + 1
        history.append(score)

        delta = 0.0 if i == 0 else score - scores[i - 1]
        smoothed = smoothed_delta(history)
        total_iterations = cycle

        # Decision logic — order matters; mirrors the bash original.
        if total_iterations >= max_iterations:
            phase, decision = "BUDGET_EXHAUSTED", "ESCALATE"
        elif i > 0 and delta < 0 and abs(delta) >= oscillation_tolerance:
            phase, decision = "REGRESSING", "ESCALATE"
        elif score >= pass_threshold and plateau_count < plateau_patience:
            if cycle >= 3 and abs(smoothed) <= plateau_threshold:
                plateau_count += 1
                if plateau_count >= plateau_patience:
                    phase, decision = "PLATEAUED", "PASS_PLATEAUED"
                else:
                    phase, decision = "PASS", "PASS"
            else:
                phase, decision = "PASS", "PASS"
        elif cycle >= 3 and abs(smoothed) <= plateau_threshold:
            plateau_count += 1
            if plateau_count >= plateau_patience:
                if score >= pass_threshold:
                    phase, decision = "PLATEAUED", "PASS_PLATEAUED"
                else:
                    phase, decision = "PLATEAUED", "ESCALATE"
            else:
                phase, decision = "IMPROVING", "CONTINUE"
        else:
            plateau_count = 0
            phase, decision = "IMPROVING", "CONTINUE"

        lines.append(
            f"cycle={cycle} score={_fmt(score)} delta={_fmt(delta)} "
            f"smoothed={_fmt(smoothed)} phase={phase} "
            f"plateau_count={plateau_count} decision={decision}"
        )

    return lines


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="convergence-engine-sim", description=__doc__)
    ap.add_argument("--scores", required=True,
                    help="Score history, comma-separated (e.g., '43,78,75,76')")
    ap.add_argument("--pass-threshold", type=int, default=80)
    ap.add_argument("--plateau-threshold", type=int, default=2)
    ap.add_argument("--plateau-patience", type=int, default=2)
    ap.add_argument("--oscillation-tolerance", type=int, default=5)
    ap.add_argument("--max-iterations", type=int, default=10)
    ap.add_argument("--target-score", type=int, default=90)
    args = ap.parse_args(argv)

    try:
        scores = [float(s.strip()) for s in args.scores.split(",") if s.strip()]
    except ValueError as exc:
        print(f"Error: invalid score in --scores: {exc}", file=sys.stderr)
        return 1
    if not scores:
        print("Error: --scores must contain at least one value", file=sys.stderr)
        return 1

    for line in simulate(
        scores,
        pass_threshold=args.pass_threshold,
        plateau_threshold=args.plateau_threshold,
        plateau_patience=args.plateau_patience,
        oscillation_tolerance=args.oscillation_tolerance,
        max_iterations=args.max_iterations,
        target_score=args.target_score,
    ):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
