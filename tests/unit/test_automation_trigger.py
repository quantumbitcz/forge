from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from hooks._py import automation_trigger_cli


def test_cli_no_automation_returns_2(tmp_path: Path):
    config = tmp_path / "forge-config.md"
    config.write_text("```yaml\nautomations:\n  enabled: false\n```\n")
    result = automation_trigger_cli.run(
        trigger="file_changed",
        payload={"file": "x.py"},
        forge_dir=tmp_path / ".forge",
        config_path=config,
    )
    assert result.exit_code == 2  # no matching automation


def test_cli_cooldown_suppresses_second_dispatch(tmp_path: Path):
    config = tmp_path / "forge-config.md"
    config.write_text(
        "```yaml\nautomations:\n  enabled: true\n  cooldown_seconds: 300\n"
        "  rules:\n    - trigger: file_changed\n      skill: forge-verify\n```\n"
    )
    r1 = automation_trigger_cli.run(
        trigger="file_changed", payload={}, forge_dir=tmp_path / ".forge", config_path=config
    )
    r2 = automation_trigger_cli.run(
        trigger="file_changed", payload={}, forge_dir=tmp_path / ".forge", config_path=config
    )
    assert r1.dispatched is True
    assert r2.dispatched is False
    assert r2.reason == "cooldown"


def test_hook_wrapper_exits_zero_without_forge_dir(tmp_path: Path, monkeypatch):
    import io
    from hooks._py.check_engine import automation_trigger as at
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO(json.dumps({"tool_input": {"file_path": "x.py"}, "tool_name": "Edit"}))
    assert at.main(stdin=stdin) == 0


def test_cli_entry_is_invokable():
    """`python3 hooks/automation_trigger.py --help` exits cleanly."""
    repo = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        [sys.executable, str(repo / "hooks" / "automation_trigger.py"), "--help"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    assert "trigger" in result.stdout.lower()
