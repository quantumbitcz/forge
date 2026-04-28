"""Solve predicate and AC math for the benchmark harness.

Spec reference: docs/superpowers/specs/2026-04-22-phase-8-measurement-design.md §2
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

_SHIPPABLE_VERDICTS: frozenset[str] = frozenset({"SHIP", "CONCERNS"})
_AC_THRESHOLD: float = 0.9


@dataclass(frozen=True)
class SolveInputs:
    pipeline_verdict: str
    partial_ac_pct: float
    critical_findings: int


def solved(inputs: SolveInputs) -> bool:
    """Three-part predicate: verdict, AC pct floor, zero criticals.

    CONCERNS counted deliberately as solved — see spec §Defence of counting CONCERNS.
    """
    if inputs.pipeline_verdict not in _SHIPPABLE_VERDICTS:
        return False
    if inputs.partial_ac_pct < _AC_THRESHOLD:
        return False
    return inputs.critical_findings == 0


def compute_partial_ac_pct(ac_breakdown: Mapping[str, str]) -> float:
    """Fraction of ACs with status PASS. UNVERIFIABLE counts as failed.

    Empty breakdown → 0.0 (no ACs to verify cannot be solved).
    """
    if not ac_breakdown:
        return 0.0
    passed = sum(1 for v in ac_breakdown.values() if v == "PASS")
    return passed / len(ac_breakdown)
