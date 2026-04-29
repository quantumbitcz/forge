"""Every text file under corpus/ is PII-clean. Invariant locked after curation."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

CORPUS = Path(__file__).resolve().parents[2] / "tests" / "evals" / "benchmark" / "corpus"
_BANNED: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("home_path_unix", re.compile(r"/Users/[^/\s<]|/home/[^/\s<]")),
    ("home_path_win", re.compile(r"C:\\Users\\[^\\<]")),
    (
        "private_ip",
        re.compile(
            r"\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})\b"
        ),
    ),
    # Matches pii_scrub.py `_AUTO_PATTERNS` internal-host entry: includes `production` to
    # keep the scrubber and this contract test in lockstep (reviewer fix 6).
    ("internal_host", re.compile(r"\b[\w-]+\.(?:internal|prod|production|corp|local)\b")),
    ("ssh_fp", re.compile(r"SHA256:[A-Za-z0-9+/]{43}=?")),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
    (
        "api_key",
        re.compile(
            r"(?i)(?:api[_-]?key|apikey|secret[_-]?key|token|bearer)\s*[:=]\s*['\"][^'\"]{8,}"
        ),
    ),
)


def _iter_text_files() -> list[Path]:
    out: list[Path] = []
    if not CORPUS.is_dir():
        return out
    for entry in CORPUS.iterdir():
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        for f in entry.iterdir():
            if f.suffix in {".md", ".yaml", ".yml", ".json"}:
                out.append(f)
    return out


@pytest.mark.parametrize("path", _iter_text_files(), ids=lambda p: f"{p.parent.name}/{p.name}")
def test_no_pii(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    for label, pat in _BANNED:
        m = pat.search(text)
        assert m is None, (
            f"{label} leaked in {path.relative_to(CORPUS)}: {m.group(0) if m else ''!r}"
        )
