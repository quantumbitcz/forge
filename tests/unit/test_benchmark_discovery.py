"""discover_corpus: filters by os_compat, rejects missing requires_docker flag."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from tests.evals.benchmark.discovery import CorpusValidationError, discover_corpus


def _write_entry(root: Path, name: str, meta: dict) -> Path:
    entry = root / name
    entry.mkdir()
    (entry / "requirement.md").write_text("# Requirement\n\ntext\n")
    (entry / "acceptance-criteria.yaml").write_text(
        "version: 1\nac_list:\n  - {id: AC-B001, description: 'long enough description here', verifiable_via: http}\n"
    )
    (entry / "expected-deliverables.yaml").write_text(
        "version: 1\nfiles_touched: {expected_any_of: [src/a.py], must_not_touch: []}\n"
    )
    (entry / "metadata.yaml").write_text(yaml.safe_dump(meta))
    (entry / "seed-project.tar.gz").write_bytes(b"\x1f\x8b\x08\x00" + b"\x00" * 40)
    return entry


def test_discovers_linux_compatible(tmp_path: Path) -> None:
    _write_entry(
        tmp_path,
        "2026-01-01-a",
        {
            "version": 1,
            "complexity": "S",
            "domain": ["api"],
            "language": "python",
            "framework": "fastapi",
            "source_run_id": "r1",
            "requires_docker": False,
            "os_compat": ["ubuntu-latest", "macos-latest", "windows-latest"],
        },
    )
    entries = discover_corpus(tmp_path, os_name="ubuntu-latest")
    assert len(entries) == 1
    assert entries[0].entry_id == "2026-01-01-a"


def test_filters_by_os_compat(tmp_path: Path) -> None:
    _write_entry(
        tmp_path,
        "2026-01-01-linux-only",
        {
            "version": 1,
            "complexity": "S",
            "domain": ["api"],
            "language": "python",
            "framework": "fastapi",
            "source_run_id": "r",
            "requires_docker": False,
            "os_compat": ["ubuntu-latest"],
        },
    )
    assert discover_corpus(tmp_path, os_name="windows-latest") == []
    assert len(discover_corpus(tmp_path, os_name="ubuntu-latest")) == 1


def test_missing_requires_docker_rejected(tmp_path: Path) -> None:
    meta = {
        "version": 1,
        "complexity": "S",
        "domain": ["api"],
        "language": "python",
        "framework": "fastapi",
        "source_run_id": "r",
        "os_compat": ["ubuntu-latest"],
    }  # no requires_docker
    _write_entry(tmp_path, "2026-01-01-bad", meta)
    with pytest.raises(CorpusValidationError, match="BENCH-METADATA-MISSING-DOCKER-FLAG"):
        discover_corpus(tmp_path, os_name="ubuntu-latest")
