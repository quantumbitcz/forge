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
    # --explicit-package-bases: avoid "Source file found twice" between the
    #   tests/evals/benchmark/ path module name and the imported
    #   tests.evals.benchmark.* dotted name (no __init__.py in tests/ root).
    # --follow-imports=silent: keep strict checking scoped to the benchmark
    #   package itself; don't drag opentelemetry / hooks/_py / pii dependents
    #   into the strict graph (those have their own non-strict ergonomics).
    r = subprocess.run(
        [
            sys.executable,
            "-m",
            "mypy",
            "--strict",
            "--explicit-package-bases",
            "--follow-imports=silent",
            "tests/evals/benchmark/",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stdout + r.stderr
