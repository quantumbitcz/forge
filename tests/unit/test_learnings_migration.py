"""Migration script tests — hybrid-v1 → schema v2, idempotent.

CI-only. Operates on copies of tests/fixtures/learnings/ only; does NOT
touch shared/learnings/.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent.parent / "fixtures" / "learnings"
SCRIPT = Path(__file__).parent.parent.parent / "scripts" / "migrate_learnings_schema.py"
DETERMINISTIC_MTIME = datetime(2026, 4, 20, 0, 0, 0, tzinfo=timezone.utc).timestamp()


def _prepare(tmp_path: Path) -> Path:
    src = FIXTURES / "spring_v1.md"
    dst = tmp_path / "spring.md"
    shutil.copy(src, dst)
    os.utime(dst, (DETERMINISTIC_MTIME, DETERMINISTIC_MTIME))
    return dst


def _run(path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--path", str(path.parent)],
        capture_output=True, text=True, check=True,
    )


def test_v1_to_v2_conversion(tmp_path):
    dst = _prepare(tmp_path)
    _run(dst)
    got = dst.read_text()
    expected = (FIXTURES / "spring_v2_expected.md").read_text().replace(
        "__FILE_MTIME__", "2026-04-20T00:00:00Z"
    )
    assert got == expected


def test_idempotent_second_run(tmp_path):
    dst = _prepare(tmp_path)
    _run(dst)
    first = dst.read_text()
    _run(dst)
    second = dst.read_text()
    assert first == second


def test_legacy_legend_drops_on_migration(tmp_path):
    """v1 frontmatter comment `HIGH→0.95` is dropped — v2 files carry no legend."""
    dst = _prepare(tmp_path)
    assert "HIGH→0.95" in dst.read_text() or "HIGH→0.95" in dst.read_text() \
        or "HIGH → 0.95" in dst.read_text()  # sanity: fixture carries the stale legend
    _run(dst)
    got = dst.read_text()
    assert "HIGH→0.95" not in got
    assert "HIGH → 0.95" not in got
    assert "schema_version: 2" in got


def test_legend_drift_warning_on_body(tmp_path):
    """If the legacy legend sits in the BODY (not frontmatter), migrator prints a WARNING."""
    path = tmp_path / "quirky.md"
    path.write_text(
        "---\n"
        "decay_tier: cross-project\n"
        "default_base_confidence: 0.75\n"
        "---\n"
        "# Quirky\n"
        "\n"
        "Note: HIGH → 0.95 in our old docs.\n"
        "\n"
        "### QR-PREEMPT-001: stub\n"
        "- **Domain:** test\n"
        "- **Confidence:** HIGH\n"
        "- **Hit count:** 0\n"
    )
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--path", str(tmp_path)],
        capture_output=True, text=True, check=True,
    )
    assert "legacy HIGH" in result.stderr
    assert "quirky.md" in result.stderr
