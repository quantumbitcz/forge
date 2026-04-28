"""Static check: `ruff check` and `mypy` pass for Phase 8 modules."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
TARGETS = [
    "tests/evals/benchmark/",
]


def test_ruff_check() -> None:
    r = subprocess.run(
        [sys.executable, "-m", "ruff", "check", *TARGETS], cwd=ROOT, capture_output=True, text=True
    )
    assert r.returncode == 0, r.stdout + r.stderr


def test_ruff_format_check() -> None:
    r = subprocess.run(
        [sys.executable, "-m", "ruff", "format", "--check", *TARGETS],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stdout + r.stderr


def test_mypy_strict() -> None:
    pytest.importorskip("mypy")
    r = subprocess.run(
        [sys.executable, "-m", "mypy", "--strict", "tests/evals/benchmark/"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stdout + r.stderr
