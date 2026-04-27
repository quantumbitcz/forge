"""Robustness tests for shared/python/findings_store.py.

Covers Phase-5 Critical 6 fix: _tiebreak no longer crashes on findings
that lack a `severity` or `confidence` field, and reduce_findings skips
schema-invalid lines with a WARNING when jsonschema is available.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
PY_LIB = REPO_ROOT / "shared" / "python"
if str(PY_LIB) not in sys.path:
    sys.path.insert(0, str(PY_LIB))

import findings_store  # noqa: E402  (path-dependent import)


@pytest.fixture()
def runs_dir(tmp_path: Path) -> Path:
    """Return an empty findings root."""
    root = tmp_path / "findings"
    root.mkdir()
    return root


def _well_formed(**overrides) -> dict:
    base = {
        "finding_id": "f-fg-410-code-reviewer-ABCDEFGHJK",
        "dedup_key": "src/foo.py:10:CONV-NAMING",
        "reviewer": "fg-410-code-reviewer",
        "severity": "WARNING",
        "category": "CONV-NAMING",
        "message": "name violates convention",
        "confidence": "MEDIUM",
        "created_at": "2026-04-27T00:00:00Z",
        "seen_by": [],
    }
    base.update(overrides)
    return base


def _write_lines(path: Path, lines: list[dict]) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for entry in lines:
            fh.write(json.dumps(entry, separators=(",", ":")) + "\n")


# ---------------------------------------------------------------------------
# _tiebreak unit tests
# ---------------------------------------------------------------------------


def test_tiebreak_missing_severity_treated_as_info():
    """Finding lacking `severity` ranks below CRITICAL peer (INFO assumed)."""
    a = {"reviewer": "fg-410-code-reviewer", "confidence": "HIGH"}  # no severity
    b = {"reviewer": "fg-411-security-reviewer", "severity": "CRITICAL", "confidence": "LOW"}
    assert findings_store._tiebreak(a, b) is b
    # Symmetric: order of arguments must not matter.
    assert findings_store._tiebreak(b, a) is b


def test_tiebreak_unknown_severity_value_treated_as_info():
    """Unknown severity (e.g., 'BLOCKER') falls back to INFO ranking."""
    a = {"reviewer": "fg-410-code-reviewer", "severity": "BLOCKER", "confidence": "HIGH"}
    b = {"reviewer": "fg-411-security-reviewer", "severity": "WARNING", "confidence": "LOW"}
    # WARNING (rank 2) beats unknown==INFO (rank 1) regardless of confidence.
    assert findings_store._tiebreak(a, b) is b
    assert findings_store._tiebreak(b, a) is b


def test_tiebreak_missing_confidence_treated_as_low():
    """Finding lacking `confidence` ranks below MEDIUM peer when severities match."""
    a = {"reviewer": "fg-411-security-reviewer", "severity": "WARNING"}  # no confidence
    b = {"reviewer": "fg-410-code-reviewer", "severity": "WARNING", "confidence": "MEDIUM"}
    assert findings_store._tiebreak(a, b) is b
    assert findings_store._tiebreak(b, a) is b


def test_tiebreak_does_not_raise_on_missing_reviewer():
    """Final ASCII tiebreak handles missing reviewer field gracefully."""
    a = {"severity": "WARNING", "confidence": "MEDIUM"}
    b = {"severity": "WARNING", "confidence": "MEDIUM", "reviewer": "fg-410-code-reviewer"}
    # Should not raise; deterministic winner depends on string compare with "".
    findings_store._tiebreak(a, b)
    findings_store._tiebreak(b, a)


# ---------------------------------------------------------------------------
# reduce_findings schema-validation tests
# ---------------------------------------------------------------------------


def test_reduce_skips_schema_invalid_line_with_warning(
    runs_dir: Path, capsys: pytest.CaptureFixture[str]
):
    """A schema-invalid line is dropped and a WARNING is written to stderr.

    Skips entirely when jsonschema is not installed (the schema gate becomes
    a no-op in that environment).
    """
    pytest.importorskip("jsonschema")
    good = _well_formed()
    # Bad: severity not in enum → schema invalid.
    bad = _well_formed(
        finding_id="f-fg-411-security-reviewer-XYZABCDEFG",
        dedup_key="src/bar.py:20:SEC-INJECTION",
        reviewer="fg-411-security-reviewer",
        severity="BLOCKER",
        category="SEC-INJECTION",
        confidence="HIGH",
    )
    _write_lines(runs_dir / "fg-410-code-reviewer.jsonl", [good])
    _write_lines(runs_dir / "fg-411-security-reviewer.jsonl", [bad])

    out = findings_store.reduce_findings(runs_dir, writer_glob="fg-4*.jsonl")
    captured = capsys.readouterr()

    keys = sorted(f["dedup_key"] for f in out)
    assert keys == ["src/foo.py:10:CONV-NAMING"]
    assert "schema-invalid" in captured.err
    assert "fg-411-security-reviewer" in captured.err


def test_reduce_skips_line_missing_required_fields_when_schema_unavailable(
    runs_dir: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
):
    """When jsonschema is unavailable, the structural fallback still drops bad lines."""
    monkeypatch.setattr(findings_store, "_jsonschema", None)
    good = _well_formed()
    # Missing dedup_key entirely.
    bad = {"reviewer": "fg-411-security-reviewer", "severity": "WARNING"}
    _write_lines(runs_dir / "fg-410-code-reviewer.jsonl", [good])
    _write_lines(runs_dir / "fg-411-security-reviewer.jsonl", [bad])

    out = findings_store.reduce_findings(runs_dir, writer_glob="fg-4*.jsonl")
    captured = capsys.readouterr()

    assert len(out) == 1
    assert out[0]["dedup_key"] == "src/foo.py:10:CONV-NAMING"
    assert "missing required field" in captured.err
