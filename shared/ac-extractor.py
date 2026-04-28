# shared/ac-extractor.py
"""Autonomous acceptance-criteria extractor used by fg-010-shaper in --autonomous mode.

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §3 (commit 660dbef7).
Pure stdlib. No third-party dependencies. Cross-platform (Windows/macOS/Linux).
"""
from __future__ import annotations

import re
from typing import Literal, TypedDict

Confidence = Literal["high", "medium", "low"]


class ACResult(TypedDict):
    objective: str
    acceptance_criteria: list[str]
    confidence: Confidence


# Pattern (a): numbered list — "1." or "1)" at start of line, optional leading whitespace.
_NUMBERED = re.compile(r"^\s*\d+[.)]\s+(.+?)\s*$", re.MULTILINE)

# Pattern (b): Given/When/Then BDD lines.
_GIVEN_WHEN_THEN = re.compile(
    r"^\s*(?:Given|When|Then)\s+(.+?)\s*$",
    re.MULTILINE | re.IGNORECASE,
)

# Pattern (c): bullet (- or *) prefixed by an imperative verb from the whitelist.
_IMPERATIVE_VERBS = (
    "must",
    "should",
    "will",
    "ensure",
    "validate",
    "return",
    "expose",
    "accept",
    "reject",
)
_IMPERATIVE = re.compile(
    r"^\s*[-*]\s+((?:" + "|".join(_IMPERATIVE_VERBS) + r")\b.+?)\s*$",
    re.MULTILINE | re.IGNORECASE,
)

_OBJECTIVE_MAX_CHARS = 200


def _classify_confidence(ac_count: int) -> Confidence:
    if ac_count < 2:
        return "low"
    if ac_count <= 4:
        return "medium"
    return "high"


def extract_acs(raw_text: str) -> ACResult:
    """Extract acceptance criteria from free-text input.

    Returns a dict with keys (objective, acceptance_criteria, confidence).
    Order-preserving deduplication via exact string match.
    """
    if not isinstance(raw_text, str):
        raise TypeError(f"raw_text must be str, got {type(raw_text).__name__}")

    matches: list[tuple[int, str]] = []
    for pattern in (_NUMBERED, _GIVEN_WHEN_THEN, _IMPERATIVE):
        for m in pattern.finditer(raw_text):
            matches.append((m.start(), m.group(1).strip()))
    matches.sort(key=lambda x: x[0])

    seen: set[str] = set()
    deduped: list[str] = []
    for _, ac in matches:
        if ac and ac not in seen:
            seen.add(ac)
            deduped.append(ac)

    confidence = _classify_confidence(len(deduped))

    objective = ""
    for line in raw_text.splitlines():
        stripped = line.strip()
        if stripped:
            objective = stripped[:_OBJECTIVE_MAX_CHARS]
            break

    return {
        "objective": objective,
        "acceptance_criteria": deduped,
        "confidence": confidence,
    }


def _main() -> int:
    """CLI entry point used by `agents/fg-010-shaper.md` autonomous mode.

    Reads free-text input from a file (or stdin via `--input -`), runs
    `extract_acs()`, and prints the JSON envelope expected by the shaper:
        {"acs": [...], "objective": "...", "confidence": "high|medium|low"}

    Exit codes:
      0 — success
      2 — input read error or `extract_acs()` raised
    """
    import argparse
    import json
    import sys

    parser = argparse.ArgumentParser(
        prog="ac-extractor",
        description="Extract acceptance criteria from free-text input.",
    )
    parser.add_argument(
        "--input",
        required=True,
        help="Path to input file, or '-' to read stdin.",
    )
    args = parser.parse_args()

    try:
        if args.input == "-":
            raw_text = sys.stdin.read()
        else:
            from pathlib import Path

            raw_text = Path(args.input).read_text(encoding="utf-8")
    except OSError as exc:
        print(f"ac-extractor: failed to read input: {exc}", file=sys.stderr)
        return 2

    try:
        result = extract_acs(raw_text)
    except (TypeError, ValueError) as exc:
        print(f"ac-extractor: extraction failed: {exc}", file=sys.stderr)
        return 2

    # Shaper consumes `acs` (list); preserve `objective` and `confidence` for
    # downstream telemetry and minimum-confidence gating.
    payload = {
        "acs": result["acceptance_criteria"],
        "objective": result["objective"],
        "confidence": result["confidence"],
    }
    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(_main())
