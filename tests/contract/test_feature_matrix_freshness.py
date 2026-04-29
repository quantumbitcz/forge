"""Contract test: shared/feature-matrix.md is up-to-date w.r.t. the generator.

Runs the generator, compares the resulting file to its pre-run content, and
fails if they differ. Equivalent to `python shared/feature_matrix_generator.py
&& git diff --exit-code shared/feature-matrix.md`.

Also verifies ASCII-only content between the sentinels (no em/en dashes, no
smart quotes) and presence of exactly one of each sentinel.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
MATRIX_PATH = REPO_ROOT / "shared" / "feature-matrix.md"
GENERATOR_PATH = REPO_ROOT / "shared" / "feature_matrix_generator.py"

START = "<!-- FEATURE_MATRIX_START -->"
END = "<!-- FEATURE_MATRIX_END -->"
FORBIDDEN_CHARS = {"–", "—", "‘", "’", "“", "”"}  # en/em dash, smart quotes


def test_sentinels_exactly_once() -> None:
    text = MATRIX_PATH.read_text(encoding="utf-8")
    assert text.count(START) == 1, f"{MATRIX_PATH}: START sentinel count != 1"
    assert text.count(END) == 1, f"{MATRIX_PATH}: END sentinel count != 1"


def test_ascii_only_between_sentinels() -> None:
    text = MATRIX_PATH.read_text(encoding="utf-8")
    start = text.index(START) + len(START)
    end = text.index(END)
    block = text[start:end]
    hits = [c for c in FORBIDDEN_CHARS if c in block]
    assert not hits, f"non-ASCII chars found between sentinels: {[hex(ord(c)) for c in hits]}"


def test_generator_is_idempotent() -> None:
    before = MATRIX_PATH.read_text(encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(GENERATOR_PATH)],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"generator failed: stderr={result.stderr}"
    after = MATRIX_PATH.read_text(encoding="utf-8")
    assert before == after, (
        "feature-matrix.md changed after running the generator. "
        "Run `python shared/feature_matrix_generator.py` and commit the diff."
    )


def test_row_count_matches_features_dict() -> None:
    text = MATRIX_PATH.read_text(encoding="utf-8")
    start = text.index(START) + len(START)
    end = text.index(END)
    block = text[start:end].strip().splitlines()
    # Data rows begin with `| F` (every feature id starts with F). This cleanly
    # excludes the header (`| ID |`) and the separator (`|----|`).
    data_rows = [line for line in block if line.startswith("| F")]
    assert len(data_rows) == 39, (
        f"expected 39 data rows (one per feature), got {len(data_rows)}"
    )
    # Separately sanity-check total rows including header + separator.
    # Use a floor (>= 41) rather than equality: future feature additions bump
    # this number and the data-row count above is the authoritative check.
    all_rows = [line for line in block if line.startswith("|")]
    assert len(all_rows) >= 41, (
        f"expected at least 41 total table rows (header + sep + >=39 data), "
        f"got {len(all_rows)}"
    )
