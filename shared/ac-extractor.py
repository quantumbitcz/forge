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
