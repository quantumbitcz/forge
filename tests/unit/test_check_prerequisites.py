"""Test the Python 3.10+ enforcement gate."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "shared" / "check_prerequisites.py"


def test_exits_zero_on_current_python():
    """Running under Python 3.10+ should succeed with exit code 0."""
    assert sys.version_info >= (3, 10), "Test harness requires Python 3.10+"
    result = subprocess.run(
        [sys.executable, str(SCRIPT)], capture_output=True, text=True
    )
    assert result.returncode == 0, f"stderr: {result.stderr}"
    assert "OK" in result.stdout


def test_rejects_python_39_when_simulated(monkeypatch):
    """When simulated version is 3.9, the script exits 1 with guidance."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--simulate-version", "3.9.16"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1
    assert "requires Python 3.10" in result.stderr
    assert "3.9.16" in result.stderr


def test_prints_upgrade_hint_per_platform():
    """Guidance includes at least one of the upgrade commands."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--simulate-version", "3.9.0"],
        capture_output=True,
        text=True,
    )
    combined = result.stdout + result.stderr
    assert "brew install python" in combined or "apt install python" in combined
