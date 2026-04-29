"""Unit tests for shared.convergence_engine_sim."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]


def _run(args: list[str]) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(REPO) + os.pathsep + env.get("PYTHONPATH", "")
    return subprocess.run(
        [sys.executable, "-m", "shared.convergence_engine_sim", *args],
        env=env, cwd=REPO, capture_output=True, text=True, check=False,
    )


def _last_decision(stdout: str) -> str:
    last = stdout.strip().splitlines()[-1]
    return [tok for tok in last.split() if tok.startswith("decision=")][0].split("=", 1)[1]


def _last_phase(stdout: str) -> str:
    last = stdout.strip().splitlines()[-1]
    return [tok for tok in last.split() if tok.startswith("phase=")][0].split("=", 1)[1]


# ---------------------------------------------------------------------------


def test_missing_scores_exits_2():
    result = _run([])
    assert result.returncode == 2  # argparse error
    assert "--scores" in result.stderr


def test_invalid_score_exits_1():
    result = _run(["--scores", "abc"])
    assert result.returncode == 1


def test_steady_climb_passes_at_threshold():
    result = _run(["--scores", "30,50,70,80"])
    assert result.returncode == 0
    assert _last_phase(result.stdout) == "PASS"
    assert _last_decision(result.stdout) == "PASS"


def test_regression_triggers_escalate():
    result = _run(["--scores", "85,40", "--oscillation-tolerance", "5"])
    assert result.returncode == 0
    assert _last_phase(result.stdout) == "REGRESSING"
    assert _last_decision(result.stdout) == "ESCALATE"


def test_sub_tolerance_drop_does_not_regress_two_cycle():
    """Drop of 3 with tolerance 5 should NOT count as regression (two-score case)."""
    result = _run(["--scores", "85,82", "--oscillation-tolerance", "5"])
    assert _last_phase(result.stdout) != "REGRESSING"


def test_plateau_below_threshold_escalates():
    result = _run(["--scores", "50,52,53,53,53",
                   "--plateau-threshold", "2", "--plateau-patience", "2"])
    # The last cycle should be PLATEAUED with ESCALATE since score < pass_threshold
    last = result.stdout.strip().splitlines()[-1]
    assert "PLATEAUED" in last
    assert "ESCALATE" in last


def test_plateau_above_threshold_pass_plateaued():
    result = _run(["--scores", "80,82,82,82,82",
                   "--plateau-threshold", "2", "--plateau-patience", "2"])
    last = result.stdout.strip().splitlines()[-1]
    assert "PLATEAUED" in last or "PASS_PLATEAUED" in last


# ---------------------------------------------------------------------------
# Phase 3: boundary-semantics tests (issue: livelock at delta == tolerance)
# ---------------------------------------------------------------------------


def test_boundary_delta_equals_tolerance_escalates():
    """A drop of exactly oscillation_tolerance must escalate (strict >= semantics).

    Under the old `>` semantics this was IMPROVING/CONTINUE. Under the Phase 3
    `>=` semantics it is REGRESSING/ESCALATE on the first full-tolerance dip.
    """
    result = _run(["--scores", "85,80", "--oscillation-tolerance", "5"])
    assert result.returncode == 0
    assert _last_phase(result.stdout) == "REGRESSING"
    assert _last_decision(result.stdout) == "ESCALATE"


def test_oscillation_at_boundary_escalates_by_cycle_5():
    """The canonical [87, 82, 87, 82, 87, ...] boundary oscillation must escalate
    no later than cycle 5 (historically, under strict `>`, it ran to max_iterations).
    """
    result = _run([
        "--scores", "87,82,87,82,87,82,87,82,87,82",
        "--oscillation-tolerance", "5",
        "--max-iterations", "20",
    ])
    assert result.returncode == 0
    lines = result.stdout.strip().splitlines()
    regressing_cycles = [
        int(tok.split("=", 1)[1])
        for line in lines
        for tok in line.split()
        if tok.startswith("cycle=") and "phase=REGRESSING" in line
    ]
    assert regressing_cycles, f"no REGRESSING cycle emitted; output: {result.stdout}"
    assert min(regressing_cycles) <= 5, (
        f"REGRESSING fired at cycle {min(regressing_cycles)}; "
        f"expected <= 5 under strict >= semantics"
    )


def test_monotonic_improvement_never_regresses():
    """Climbing scores must never emit REGRESSING, regardless of tolerance."""
    result = _run([
        "--scores", "40,55,70,85,95",
        "--oscillation-tolerance", "5",
    ])
    assert result.returncode == 0
    for line in result.stdout.strip().splitlines():
        assert "phase=REGRESSING" not in line, f"unexpected REGRESSING: {line}"


def test_oscillation_within_tolerance_does_not_regress():
    """Deltas of 2 at tolerance 5 must not regress under either old or new semantics.

    This is the partner assertion to test_boundary_delta_equals_tolerance_escalates —
    we are asserting that `>=` did NOT over-trigger on sub-tolerance wobble.
    The five-score alternating sequence guards the same invariant across 3+ cycles
    where smoothed_delta starts to matter. The two-score sub-tolerance case is
    covered separately by `test_sub_tolerance_drop_does_not_regress_two_cycle`.
    """
    result = _run([
        "--scores", "82,84,82,84,82",
        "--oscillation-tolerance", "5",
    ])
    assert result.returncode == 0
    for line in result.stdout.strip().splitlines():
        assert "phase=REGRESSING" not in line, f"unexpected REGRESSING: {line}"


def test_budget_exhausted_at_max_iterations():
    result = _run(["--scores", "10,20,30,40,50,60,70,80,82,82",
                   "--max-iterations", "10"])
    assert _last_phase(result.stdout) == "BUDGET_EXHAUSTED"


def test_budget_exhaustion_supersedes_regression_at_boundary():
    """At exactly max_iterations with a regression dip, BUDGET_EXHAUSTED wins.

    Pins the simulator's current decision ordering (see
    `shared/convergence_engine_sim.py`): the budget check runs before the
    regression check, so a cycle that would otherwise be REGRESSING is
    classified as BUDGET_EXHAUSTED when total_iterations >= max_iterations.

    Scores [90, 50] with max_iterations=2: cycle 2 hits the budget boundary
    AND |delta|=40 >= tolerance=5 — must report BUDGET_EXHAUSTED, not
    REGRESSING.
    """
    result = _run([
        "--scores", "90,50",
        "--max-iterations", "2",
        "--oscillation-tolerance", "5",
    ])
    assert result.returncode == 0
    assert _last_phase(result.stdout) == "BUDGET_EXHAUSTED"
    assert _last_decision(result.stdout) == "ESCALATE"


@pytest.mark.parametrize("scores,expected_phases", [
    # Single score: must IMPROVING
    ("50", ["IMPROVING"]),
    # Two scores climbing
    ("50,70", ["IMPROVING", "IMPROVING"]),
])
def test_first_cycles_always_improving(scores, expected_phases):
    result = _run(["--scores", scores])
    assert result.returncode == 0
    actual = []
    for line in result.stdout.strip().splitlines():
        for tok in line.split():
            if tok.startswith("phase="):
                actual.append(tok.split("=", 1)[1])
    assert actual == expected_phases


def test_smoothed_delta_helper():
    """Direct unit test of the pure-function helper."""
    sys.path.insert(0, str(REPO))
    try:
        from shared.convergence_engine_sim import smoothed_delta  # noqa: WPS433
    finally:
        sys.path.pop(0)

    assert smoothed_delta([]) == 0.0
    assert smoothed_delta([50]) == 0.0
    assert smoothed_delta([50, 60]) == 10.0
    # 3-point: d1=10, d2=10 → 10*0.6 + 10*0.4 = 10.0
    assert smoothed_delta([40, 50, 60]) == pytest.approx(10.0)
    # 4-point: d1=10, d2=10, d3=10 → 10*0.5 + 10*0.3 + 10*0.2 = 10.0
    assert smoothed_delta([30, 40, 50, 60]) == pytest.approx(10.0)
    # Mixed: scores [10, 20, 15, 25]
    # d1 = 25-15 = 10, d2 = 15-20 = -5, d3 = 20-10 = 10
    # → 10*0.5 + -5*0.3 + 10*0.2 = 5.5
    assert smoothed_delta([10, 20, 15, 25]) == pytest.approx(5.5)
