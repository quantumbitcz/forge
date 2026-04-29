"""Contract test: agents/fg-100-orchestrator.md stays under 2200 lines.

Single-tier — fail at >2200, pass silently below. No soft-warn (per spec
Open Question 1 resolution).

Rationale: orchestrator loads once per run, so size is not a per-stage token
cost. Phase 7 Wave 4 added voting-gate pseudocode (1840 → 1949). Mega C
consolidation (C2) added Stage 0.5 BRAINSTORM, §0.4d Platform Detection,
and the §0.1 dispatch matrix (1976 → 2104), so the cap moves 2000 → 2200
to retain growth headroom. Beyond 2200, the rule is "extract generic
content into shared/agent-defaults.md per the authoring rule in
shared/agent-philosophy.md."
"""
from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ORCHESTRATOR = REPO_ROOT / "agents" / "fg-100-orchestrator.md"
MAX_LINES = 2200


def test_orchestrator_file_exists() -> None:
    assert ORCHESTRATOR.exists(), f"load-bearing file missing: {ORCHESTRATOR}"


def test_orchestrator_line_count_under_budget() -> None:
    n = sum(1 for _ in ORCHESTRATOR.read_text(encoding="utf-8").splitlines())
    assert n <= MAX_LINES, (
        f"fg-100-orchestrator.md has {n} lines; budget is {MAX_LINES}. "
        "See shared/agent-philosophy.md §fg-100 size budget: extract generic "
        "content into shared/agent-defaults.md rather than expanding the cap."
    )
