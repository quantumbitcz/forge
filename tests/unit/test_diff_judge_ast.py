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
