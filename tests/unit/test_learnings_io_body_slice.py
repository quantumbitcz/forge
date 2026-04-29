"""Body-slice regression test: real prose only, never frontmatter spillage.

The pre-fix slicer searched anchor strings across the whole file, so the
``body_ref`` value in YAML frontmatter matched first and the slice scooped
up YAML lines (``schema_version:``, ``items:``, etc.). After the fix:

* ``_body_slice`` skips past the frontmatter using FRONTMATTER_RE.end().
* Anchors are matched as ``id="<X>"`` to align with ``<a id="X"></a>``
  prose markers.
* ``body_ref`` values may be bare (``X``) or legacy hashed (``#X``).
"""
from __future__ import annotations

from pathlib import Path

import pytest

from hooks._py.learnings_io import _body_slice, parse_file


REPO_ROOT = Path(__file__).resolve().parents[2]
SPRING_LEARNINGS = REPO_ROOT / "shared" / "learnings" / "spring.md"


@pytest.mark.skipif(
    not SPRING_LEARNINGS.exists(),
    reason="shared/learnings/spring.md missing in this checkout",
)
def test_spring_items_render_real_prose():
    items = parse_file(SPRING_LEARNINGS)
    assert items, "expected at least one v2 item in spring.md"
    first = items[0]
    body = first.body
    assert body, "body must not be empty after slice fix"
    # Sanity: prose, not YAML.
    assert "schema_version:" not in body
    assert "body_ref:" not in body
    assert "applied_count:" not in body
    # Spring KS-PREEMPT-001 prose mentions R2DBC fetch-then-set behaviour.
    assert "R2DBC" in body or "Domain" in body or "Pattern" in body


def test_body_slice_strips_leading_hash(tmp_path):
    raw = (
        "---\n"
        "schema_version: 2\n"
        "items:\n"
        '  - id: "foo"\n'
        '    body_ref: "#foo"\n'
        "---\n"
        '<a id="foo"></a>\nReal prose body here.\n'
    )
    out = _body_slice(raw, "#foo")
    assert "Real prose body here." in out
    assert "schema_version" not in out


def test_body_slice_bare_id(tmp_path):
    raw = (
        "---\n"
        "schema_version: 2\n"
        "items:\n"
        '  - id: "bar"\n'
        '    body_ref: "bar"\n'
        "---\n"
        '<a id="bar"></a>\nBare-id prose.\n'
    )
    out = _body_slice(raw, "bar")
    assert "Bare-id prose." in out


def test_body_slice_skips_frontmatter_field_match():
    """Even if the anchor literal appears in the frontmatter (as the
    body_ref value itself), the slicer must not match it — only the
    post-frontmatter HTML anchor counts."""
    raw = (
        "---\n"
        "schema_version: 2\n"
        "items:\n"
        '  - id: "only-in-frontmatter"\n'
        '    body_ref: "only-in-frontmatter"\n'
        "---\n"
        "# heading\nNo HTML anchor here.\n"
    )
    out = _body_slice(raw, "only-in-frontmatter")
    assert out == ""


def test_body_slice_empty_anchor():
    assert _body_slice("anything", "") == ""
    assert _body_slice("anything", "#") == ""
