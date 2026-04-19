from __future__ import annotations

from pathlib import Path

from hooks._py import platform_support as ps


def test_detect_os_returns_allowed_value():
    assert ps.detect_os() in {"darwin", "linux", "windows", "wsl"}


def test_detect_os_never_returns_gitbash():
    """Git Bash users now report 'windows' via platform.system()."""
    assert ps.detect_os() != "gitbash"


def test_forge_dir_returns_pathlib(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    result = ps.forge_dir()
    assert isinstance(result, Path)
    assert result.name == ".forge"


def test_python_executable_is_resolvable():
    assert ps.python_executable()  # non-empty


def test_is_wsl_returns_bool():
    assert isinstance(ps.is_wsl(), bool)


def test_has_command_known_tool():
    # python3 is guaranteed on all test runners
    assert ps.has_command("python3") or ps.has_command("python")
