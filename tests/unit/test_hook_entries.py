from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

HOOKS = Path(__file__).resolve().parents[2] / "hooks"

ENTRY_SCRIPTS = [
    "pre_tool_use.py",
    "post_tool_use.py",
    "post_tool_use_skill.py",
    "post_tool_use_agent.py",
    "stop.py",
    "session_start.py",
]


def _invoke(script: str, stdin: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(HOOKS / script)],
        input=stdin,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_all_entry_scripts_exist():
    for s in ENTRY_SCRIPTS:
        assert (HOOKS / s).exists(), f"missing {s}"


def test_each_entry_script_exits_zero_on_empty_stdin(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)  # no .forge/ present → all should exit 0
    for s in ENTRY_SCRIPTS:
        r = _invoke(s, "")
        assert r.returncode == 0, f"{s} exit={r.returncode} stderr={r.stderr}"


def test_hooks_json_references_python_entries():
    hooks_json = HOOKS / "hooks.json"
    data = json.loads(hooks_json.read_text())
    commands = []
    for slot in data["hooks"].values():
        for block in slot:
            for cmd in block.get("hooks", []):
                commands.append(cmd.get("command", ""))
    # Every command must be python3-invoked and point at a hooks/*.py file.
    assert commands, "hooks.json has no commands"
    for c in commands:
        assert c.startswith("python3 ${CLAUDE_PLUGIN_ROOT}/hooks/"), c
        assert c.endswith(".py"), c
    # And no .sh references anywhere.
    assert not any(".sh" in c for c in commands)


def test_hooks_json_entries_all_resolve():
    hooks_json = HOOKS / "hooks.json"
    data = json.loads(hooks_json.read_text())
    for slot in data["hooks"].values():
        for block in slot:
            for cmd in block.get("hooks", []):
                script = cmd["command"].split()[-1].replace(
                    "${CLAUDE_PLUGIN_ROOT}", str(HOOKS.parent)
                )
                assert Path(script).exists(), f"missing script: {script}"
