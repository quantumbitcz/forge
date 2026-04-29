"""Contract test: tree-sitter test-extra deps stay pinned.

Phase 7 Wave 3 (F36 voting). The diff judge depends on
tree-sitter-language-pack 1.6.2+ (latest stable on PyPI; the next
published rev is the 2.0 alpha line) for cross-language AST fingerprinting.
A version drift below 1.6.x would silently degrade the judge to textual
fallback for TS/JS/Kotlin/Go/Rust/Java/C/C++/Ruby/PHP/Swift, hiding real
divergences.
"""
from pathlib import Path

try:  # tomllib is stdlib in 3.11+; fall back to tomli on 3.10
    import tomllib
except ImportError:  # pragma: no cover
    import tomli as tomllib  # type: ignore[no-redef]

PYPROJECT = tomllib.loads(
    (Path(__file__).parent.parent.parent / "pyproject.toml").read_text(encoding="utf-8")
)


def test_tree_sitter_language_pack_in_test_extras():
    test_extra = PYPROJECT["project"]["optional-dependencies"]["test"]
    assert any(dep.startswith("tree-sitter-language-pack") for dep in test_extra), test_extra


def test_version_pinned_with_upper_bound():
    test_extra = PYPROJECT["project"]["optional-dependencies"]["test"]
    tsp = next(d for d in test_extra if d.startswith("tree-sitter-language-pack"))
    assert ">=1.6.2" in tsp and "<2.0" in tsp, tsp


def test_tree_sitter_core_pinned():
    test_extra = PYPROJECT["project"]["optional-dependencies"]["test"]
    ts = next(d for d in test_extra if d.startswith("tree-sitter") and "language-pack" not in d)
    assert ">=0.25.2" in ts and "<0.26" in ts, ts
