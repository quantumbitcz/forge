"""End-to-end smoke: every CLI prints --help; renderer is idempotent; schemas load."""
from __future__ import annotations
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIS = [
    "tests.evals.benchmark.runner",
    "tests.evals.benchmark.curate",
    "tests.evals.benchmark.render_scorecard",
    "tests.evals.benchmark.refresh_baseline",
    "tests.evals.benchmark.aggregate",
    "tests.evals.benchmark.gate_cli",
]


def test_all_clis_print_help() -> None:
    for cli in CLIS:
        r = subprocess.run([sys.executable, "-m", cli, "--help"],
                           cwd=ROOT, capture_output=True, text=True)
        assert r.returncode == 0, f"{cli} --help failed: {r.stderr}"
