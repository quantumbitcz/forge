"""must_not_touch violations detected via git status in benchmark target."""

from __future__ import annotations

import subprocess
from pathlib import Path

from tests.evals.benchmark.live_run import _detect_must_not_touch


def test_detects_forbidden_path(tmp_path: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    (tmp_path / "package-lock.json").write_text("{}")
    (tmp_path / ".github").mkdir()
    (tmp_path / ".github" / "workflows" / "bad.yml").parent.mkdir(parents=True, exist_ok=True)
    (tmp_path / ".github" / "workflows" / "bad.yml").write_text("bad\n")
    vios = _detect_must_not_touch(tmp_path, ["package-lock.json", ".github/**"])
    assert set(vios) == {"package-lock.json", ".github/**"}


def test_no_violations(tmp_path: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    (tmp_path / "src.py").write_text("x=1\n")
    assert _detect_must_not_touch(tmp_path, ["package-lock.json"]) == []


def test_detects_rename_destination(tmp_path: Path) -> None:
    """`git mv old.py forbidden/x.py` is flagged via the rename destination path."""
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.email", "a@b.c"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    (tmp_path / "old.py").write_text("# safe\n")
    subprocess.run(["git", "add", "old.py"], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=tmp_path, check=True)
    (tmp_path / ".github").mkdir()
    subprocess.run(["git", "mv", "old.py", ".github/x.py"], cwd=tmp_path, check=True)
    vios = _detect_must_not_touch(tmp_path, [".github/**"])
    assert vios == [".github/**"]
