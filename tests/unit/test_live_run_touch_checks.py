"""must_not_touch violations detected via git status in benchmark target."""
from __future__ import annotations
from pathlib import Path
import subprocess
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
