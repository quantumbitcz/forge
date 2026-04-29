"""Coverage-reporter canary: run the reporter against a 4-row synthetic table
with 2 scenarios covering 3 rows, assert the output shows 75%.

Rationale: if the reporter always prints 100% or 0%, this canary catches it.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIX = REPO / "tests" / "mutation" / "fixtures"


def test_coverage_reporter_produces_expected_percentage(tmp_path):
    # Stage a miniature repo layout the reporter expects.
    synth_shared = tmp_path / "shared"
    synth_shared.mkdir()
    shutil.copy(FIX / "synthetic-state-transitions.md",
                synth_shared / "state-transitions.md")

    synth_scenarios = tmp_path / "tests" / "scenario"
    synth_scenarios.mkdir(parents=True)
    shutil.copy(FIX / "synthetic-scenario-a.bats",
                synth_scenarios / "synthetic-a.bats")
    shutil.copy(FIX / "synthetic-scenario-b.bats",
                synth_scenarios / "synthetic-b.bats")

    # Import the reporter as a module but patch its REPO constant.
    sys.path.insert(0, str(REPO))
    try:
        import importlib
        mod = importlib.import_module("tests.scenario.report_coverage")
        mod.TABLE = synth_shared / "state-transitions.md"
        mod.SCENARIO_DIR = synth_scenarios
        mod.COVERAGE_MD = tmp_path / "COVERAGE.md"
        rc = mod.main([])
        assert rc == 0
        rendered = mod.COVERAGE_MD.read_text(encoding="utf-8")
        # 3 of 4 T-* rows covered → 75.0%
        assert "75.0%" in rendered, rendered
        assert "| T-01 | " in rendered
        # Row 4 is NOT covered.
        row_4 = [line for line in rendered.splitlines()
                 if line.startswith("| T-04 |")][0]
        assert row_4.endswith("NO |")
    finally:
        sys.path.pop(0)
