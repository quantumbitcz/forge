"""Structural test: Phase 8 benchmark skeleton exists and imports cleanly."""
from __future__ import annotations
from pathlib import Path
import importlib

ROOT = Path(__file__).resolve().parents[2]
BENCH = ROOT / "tests" / "evals" / "benchmark"


def test_directory_tree() -> None:
    for sub in ("corpus", "results", "schemas", "fixtures"):
        assert (BENCH / sub).is_dir(), f"missing {sub}/"
    assert (BENCH / "__init__.py").is_file()
    assert (BENCH / "README.md").is_file()


def test_modules_importable() -> None:
    for mod in (
        "tests.evals.benchmark",
        "tests.evals.benchmark.scoring",
        "tests.evals.benchmark.runner",
        "tests.evals.benchmark.curate",
        "tests.evals.benchmark.render_scorecard",
        "tests.evals.benchmark.refresh_baseline",
        "tests.evals.benchmark.write_forge_model_overrides",
    ):
        importlib.import_module(mod)
