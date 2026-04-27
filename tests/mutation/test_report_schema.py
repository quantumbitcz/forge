"""Schema-lock test for tests/mutation/REPORT.md.

If someone reorders columns, renames a header, or drops one, this test
catches it BEFORE CI does. Cheap (parses one markdown table) and worth it
because the report is the only artefact a reviewer reads to interpret
mutation outcomes.
"""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
REPORT = REPO / "tests" / "mutation" / "REPORT.md"

EXPECTED_HEADERS = [
    "row_id",
    "description",
    "scenario",
    "mutation_applied",
    "baseline",
    "outcome",
]


def _parse_first_table_headers(md: str) -> list[str]:
    """Return the cells of the first markdown table header row in `md`.

    Skips blockquote-style table-looking lines and table separators
    (`| --- | --- |`). The first non-separator pipe-row is the header.
    """
    for raw in md.splitlines():
        line = raw.rstrip()
        if not line.startswith("|"):
            continue
        # Skip the `| --- | ---` separator row.
        cells = [c.strip() for c in line.strip("|").split("|")]
        if all(set(c) <= {"-", " "} for c in cells if c):
            continue
        return cells
    raise AssertionError("no markdown table header row found in REPORT.md")


def test_report_md_exists() -> None:
    assert REPORT.is_file(), f"missing {REPORT}"


def test_report_md_column_count() -> None:
    headers = _parse_first_table_headers(REPORT.read_text(encoding="utf-8"))
    assert len(headers) == len(EXPECTED_HEADERS), (
        f"expected {len(EXPECTED_HEADERS)} columns, got {len(headers)}: {headers}"
    )


def test_report_md_column_headers() -> None:
    headers = _parse_first_table_headers(REPORT.read_text(encoding="utf-8"))
    assert headers == EXPECTED_HEADERS, (
        f"column headers drifted; expected {EXPECTED_HEADERS}, got {headers}"
    )


def test_report_md_outcome_values_use_canonical_strings() -> None:
    """Every outcome cell must be one of the three canonical strings."""
    canonical = {"killed", "**survived (gap)**", "**baseline broken**"}
    text = REPORT.read_text(encoding="utf-8")
    rows = [line for line in text.splitlines() if line.startswith("| ")]
    # Drop the header row + separator.
    body = rows[2:]
    assert body, "REPORT.md has no body rows"
    for line in body:
        cells = [c.strip() for c in line.strip("|").split("|")]
        outcome = cells[-1]
        assert outcome in canonical, (
            f"row outcome {outcome!r} not in canonical set {canonical}"
        )
