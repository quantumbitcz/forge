"""Aggregator counts lines in per-cell .hook-failures.jsonl artefacts."""

from __future__ import annotations

import json
from pathlib import Path

from tests.evals.benchmark.aggregate import count_hook_failures


def test_sums_across_cells(tmp_path: Path) -> None:
    for os_name, model, n in [
        ("ubuntu-latest", "claude-sonnet-4-6", 2),
        ("ubuntu-latest", "claude-opus-4-7", 1),
    ]:
        d = tmp_path / f"{os_name}-{model}"
        d.mkdir()
        (d / ".hook-failures.jsonl").write_text("\n".join(json.dumps({"e": "x"}) for _ in range(n)))
    assert count_hook_failures(tmp_path) == 3


def test_missing_file_zero(tmp_path: Path) -> None:
    assert count_hook_failures(tmp_path) == 0
