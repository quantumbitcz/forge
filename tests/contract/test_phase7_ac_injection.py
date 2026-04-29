"""Phase 7 coordination: the runner seeds .forge/specs/index.json correctly."""

from __future__ import annotations

import json
from pathlib import Path

from tests.evals.benchmark.discovery import CorpusEntry
from tests.evals.benchmark.live_run import _write_spec_injection


def test_source_field_present_and_untouched(tmp_path: Path) -> None:
    entry = CorpusEntry(
        entry_id="demo",
        path=tmp_path,
        requirement="# Requirement\nx\n",
        ac_list=[{"id": "AC-B001", "description": "X works", "verifiable_via": "cli"}],
        expected={},
        metadata={"complexity": "S", "requires_docker": False},
    )
    project = tmp_path / "project"
    project.mkdir()
    _write_spec_injection(project, entry)
    doc = json.loads((project / ".forge" / "specs" / "index.json").read_text(encoding="utf-8"))
    assert doc["specs"]["demo"]["source"] == "benchmark-injected"


def test_namespace_does_not_collide_with_ac_numeric() -> None:
    """AC-B* namespace is disjoint from AC-NNN (forge-generated)."""
    import re

    bench_pat = re.compile(r"^AC-B\d{3}$")
    forge_pat = re.compile(r"^AC-\d{3}$")
    assert bench_pat.match("AC-B001")
    assert not bench_pat.match("AC-001")
    assert not forge_pat.match("AC-B001")
