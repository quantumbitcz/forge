"""Contract test: agents/fg-100-orchestrator.md stays under 1800 lines.

Single-tier — fail at >1800, pass silently below. No soft-warn (per spec
Open Question 1 resolution).

Rationale: orchestrator loads once per run, so size is not a per-stage token
cost. But 1557 → 1800 headroom exists for growth. Beyond 1800, the rule is
"extract generic content into shared/agent-defaults.md per the authoring
rule in shared/agent-philosophy.md."
"""
from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
ORCHESTRATOR = REPO_ROOT / "agents" / "fg-100-orchestrator.md"
MAX_LINES = 1800


def test_orchestrator_file_exists() -> None:
    assert ORCHESTRATOR.exists(), f"load-bearing file missing: {ORCHESTRATOR}"


def test_orchestrator_line_count_under_budget() -> None:
    n = sum(1 for _ in ORCHESTRATOR.read_text(encoding="utf-8").splitlines())
    assert n <= MAX_LINES, (
        f"fg-100-orchestrator.md has {n} lines; budget is {MAX_LINES}. "
        "See shared/agent-philosophy.md §fg-100 size budget: extract generic "
        "content into shared/agent-defaults.md rather than expanding the cap."
    )
