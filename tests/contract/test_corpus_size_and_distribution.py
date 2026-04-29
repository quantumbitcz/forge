"""Release gate: ≥10 entries, language/framework spread."""

from __future__ import annotations

import os
from pathlib import Path

import pytest
import yaml

CORPUS = Path(__file__).resolve().parents[2] / "tests" / "evals" / "benchmark" / "corpus"


def _entries() -> list[Path]:
    if not CORPUS.is_dir():
        return []
    return [p for p in CORPUS.iterdir() if p.is_dir() and not p.name.startswith(".")]


@pytest.mark.skipif(
    os.environ.get("PHASE_8_CORPUS_GATE") != "1",
    reason="Gate enabled only on release branches (set PHASE_8_CORPUS_GATE=1)",
)
def test_corpus_has_min_entries() -> None:
    assert len(_entries()) >= 10, "AC-801: release requires ≥ 10 corpus entries"


@pytest.mark.skipif(os.environ.get("PHASE_8_CORPUS_GATE") != "1", reason="release-only")
def test_language_and_framework_spread() -> None:
    langs, frameworks, complexities = set(), set(), []
    for e in _entries():
        meta = yaml.safe_load((e / "metadata.yaml").read_text(encoding="utf-8"))
        langs.add(meta["language"])
        frameworks.add(meta["framework"])
        complexities.append(meta["complexity"])
    assert len(langs) >= 3
    assert len(frameworks) >= 3
    s = complexities.count("S")
    m = complexities.count("M")
    total = len(complexities)
    assert 0.25 <= s / total <= 0.55
    assert 0.25 <= m / total <= 0.55
