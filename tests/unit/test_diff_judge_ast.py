from pathlib import Path

import pytest

from hooks._py.diff_judge import judge


def _make_sample(tmp_path: Path, name: str, files: dict[str, str]) -> Path:
    root = tmp_path / name
    for rel, content in files.items():
        parts = rel.split("/")
        p = root
        for part in parts:
            p = p / part
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
    return root


def test_python_same_whitespace_and_comment_only(tmp_path):
    a = _make_sample(tmp_path, "a", {"src/m.py":
        "def f(x):\n    return x + 1\n"})
    b = _make_sample(tmp_path, "b", {"src/m.py":
        "# leading comment\ndef f( x ):\n\n    return x + 1  # trailing\n"})
    r = judge(a, b, ["src/m.py"])
    assert r.verdict == "SAME"
    assert r.confidence == "HIGH"
    assert r.degraded_files == []


def test_python_diverges_on_logic_change(tmp_path):
    a = _make_sample(tmp_path, "a", {"src/m.py": "def f(x):\n    return x + 1\n"})
    b = _make_sample(tmp_path, "b", {"src/m.py": "def f(x):\n    return x - 1\n"})
    r = judge(a, b, ["src/m.py"])
    assert r.verdict == "DIVERGES"
    assert len(r.divergences) == 1
    assert r.divergences[0]["file"] == "src/m.py"


def test_python_parse_failure_falls_back_to_degraded(tmp_path):
    a = _make_sample(tmp_path, "a", {"src/m.py": "def f(x):\n   return x +\n"})  # syntax error
    b = _make_sample(tmp_path, "b", {"src/m.py": "def f(x):\n   return x +\n"})
    r = judge(a, b, ["src/m.py"])
    assert r.verdict == "SAME"  # byte-identical after normalization
    assert "src/m.py" in r.degraded_files


def test_typescript_same_whitespace_only(tmp_path):
    pytest.importorskip("tree_sitter_language_pack")
    a = _make_sample(tmp_path, "a", {"src/m.ts": "export const f = (x: number) => x + 1;"})
    b = _make_sample(tmp_path, "b", {"src/m.ts":
        "// comment\nexport  const  f = ( x : number ) => x + 1;"})
    r = judge(a, b, ["src/m.ts"])
    assert r.verdict == "SAME"


def test_unsupported_language_uses_degraded(tmp_path):
    a = _make_sample(tmp_path, "a", {"src/m.ex": "defmodule M do\n  def f(x), do: x + 1\nend\n"})
    b = _make_sample(tmp_path, "b", {"src/m.ex": "defmodule M do\n  def f(x), do: x + 1\nend\n"})
    r = judge(a, b, ["src/m.ex"])
    assert r.verdict == "SAME"
    assert "src/m.ex" in r.degraded_files
    assert r.confidence == "LOW"


def test_file_in_only_one_sample_diverges(tmp_path):
    a = _make_sample(tmp_path, "a", {"src/m.py": "x = 1"})
    b = _make_sample(tmp_path, "b", {})
    r = judge(a, b, ["src/m.py"])
    assert r.verdict == "DIVERGES"


def test_empty_touched_files_raises(tmp_path):
    """judge() refuses to opine when there's nothing to compare."""
    a = _make_sample(tmp_path, "a", {})
    b = _make_sample(tmp_path, "b", {})
    with pytest.raises(ValueError):
        judge(a, b, [])


def test_all_file_presence_only_yields_low_confidence(tmp_path):
    """When EVERY comparison was file-presence-only (we never opened any
    file's contents), the judge has no opinion on what's actually present —
    confidence must be LOW even though the verdict is structurally meaningful.
    """
    a = _make_sample(tmp_path, "a", {"src/m.py": "x = 1"})
    b = _make_sample(tmp_path, "b", {})
    r = judge(a, b, ["src/m.py"])
    assert r.verdict == "DIVERGES"
    assert r.confidence == "LOW"


def test_deeply_nested_file_does_not_blow_recursion(tmp_path):
    """The iterative DFS in tup() must tolerate deep CSTs that the prior
    recursive form would overflow on."""
    pytest.importorskip("tree_sitter_language_pack")
    # Build a 2000-deep nested expression: f(f(f(...(x))))
    depth = 2000
    open_parens = "f(" * depth
    close_parens = ")" * depth
    src = f"export const y = {open_parens}x{close_parens};"
    a = _make_sample(tmp_path, "a", {"src/deep.ts": src})
    b = _make_sample(tmp_path, "b", {"src/deep.ts": src})
    r = judge(a, b, ["src/deep.ts"])
    assert r.verdict == "SAME"
