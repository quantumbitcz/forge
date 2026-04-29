"""Render-twice, diff-exit-code=0 — second render produces same bytes."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_render_is_idempotent(tmp_path: Path) -> None:
    trends = tmp_path / "trends.jsonl"
    trends.write_text(
        '{"schema_version":1,"week_of":"2026-04-27","commit_sha":"abc","forge_version":"6.0.0","cells":[],"hook_failures_total":0,"regressions":[]}\n'
    )
    out1 = tmp_path / "a.md"
    out2 = tmp_path / "b.md"
    for target in (out1, out2):
        r = subprocess.run(
            [
                sys.executable,
                "-m",
                "tests.evals.benchmark.render_scorecard",
                "--trends",
                str(trends),
                "--output",
                str(target),
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        assert r.returncode == 0
    assert out1.read_bytes() == out2.read_bytes()
