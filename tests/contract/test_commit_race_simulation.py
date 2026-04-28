"""Race retry: if push fails once, fetch+rebase; second failure → upload only."""
from __future__ import annotations

from pathlib import Path

# The workflow logic is in YAML, but the shell block can be extracted as a script.
# Assert the retry loop pattern is present in benchmark.yml.


def test_workflow_has_race_retry_loop() -> None:
    wf = (Path(__file__).resolve().parents[2] / ".github" / "workflows" / "benchmark.yml").read_text()
    assert "for i in 1 2; do" in wf
    assert "BENCH-COMMIT-RACE" in wf
    assert "Upload scorecard (race fallback)" in wf or "scorecard-${{ github.run_id }}" in wf
