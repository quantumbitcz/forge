"""curate.py CLI: --help exits 0; sandbox refuses non-corpus writes."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_help() -> None:
    r = subprocess.run(
        [sys.executable, "-m", "tests.evals.benchmark.curate", "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0
    assert "corpus" in r.stdout.lower()


def test_sandbox_boundary(tmp_path: Path) -> None:
    import pytest

    from tests.evals.benchmark.curate import CurationError, _write_entry

    outside = tmp_path / "not-in-corpus"
    with pytest.raises(CurationError, match="outside corpus root"):
        _write_entry(
            corpus_root=tmp_path / "corpus",
            target_dir=outside,
            requirement="x",
            ac_list=[],
            expected={},
            metadata={},
            seed_tarball=tmp_path / "x.tar.gz",
        )
