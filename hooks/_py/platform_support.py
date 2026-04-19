"""OS detection, executable lookup, forge-dir resolution."""
from __future__ import annotations

import os
import platform
import shutil
import sys
from pathlib import Path


def detect_os() -> str:
    """Return one of {'darwin', 'linux', 'windows', 'wsl'}."""
    system = platform.system().lower()
    if system == "windows":
        return "windows"
    if system == "darwin":
        return "darwin"
    if system == "linux":
        return "wsl" if is_wsl() else "linux"
    return system or "unknown"


def is_wsl() -> bool:
    if platform.system().lower() != "linux":
        return False
    try:
        with open("/proc/version", "r", encoding="utf-8") as f:
            contents = f.read().lower()
    except OSError:
        return False
    return "microsoft" in contents or "wsl" in contents


def forge_dir(root: Path | None = None) -> Path:
    """Return the `.forge/` directory for the given project root (defaults to cwd)."""
    return (root or Path.cwd()) / ".forge"


def python_executable() -> str:
    """Return the best Python executable, preferring sys.executable."""
    return sys.executable or shutil.which("python3") or shutil.which("python") or "python3"


def has_command(name: str) -> bool:
    return shutil.which(name) is not None


def temp_dir() -> Path:
    """Return a platform-appropriate scratch directory for hook workspaces."""
    import tempfile
    return Path(tempfile.gettempdir())


def env_bool(name: str, default: bool = False) -> bool:
    """Read a yes/no environment variable (1/true/yes/on)."""
    val = os.environ.get(name)
    if val is None:
        return default
    return val.strip().lower() in {"1", "true", "yes", "on"}
