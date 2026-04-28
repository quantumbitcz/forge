"""End-to-end: the runner consumes a fixture corpus in dry-run mode and emits valid results.

No `claude` CLI invoked — uses the same --dry-run posture as the pipeline runner.
"""
from __future__ import annotations
import json
from pathlib import Path
import subprocess
import sys
import pytest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_ROOT = ROOT / "tests" / "evals" / "benchmark" / "fixtures" / "synthetic-corpus"


@pytest.mark.skip(reason="enabled by Task 9 dry-run runner")
def test_dry_run_end_to_end(tmp_path: Path) -> None:
    results_root = tmp_path / "results"
    result = subprocess.run(
        [sys.executable, "-m", "tests.evals.benchmark.runner",
         "--corpus-root", str(FIXTURE_ROOT),
         "--results-root", str(results_root),
         "--os", "ubuntu-latest",
         "--model", "claude-sonnet-4-6",
         "--dry-run",
         "--parallel", "1"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    assert "discovered 1 corpus entries" in result.stderr
    out_files = list(results_root.rglob("*.json"))
    assert len(out_files) == 1
    payload = json.loads(out_files[0].read_text())
    assert payload["schema_version"] == 1
    assert payload["entry_id"] == "2026-01-01-hello-health"
    assert payload["pipeline_verdict"] == "DRY_RUN"
    assert payload["solved"] is False  # DRY_RUN never counts as solved
