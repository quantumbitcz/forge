"""CLI dispatcher — write / list / show / resume / search."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from hooks._py.handoff.cli import main as cli_main


def test_write_creates_file(tmp_path, monkeypatch):
    forge = tmp_path / ".forge"
    forge.mkdir()
    (forge / "state.json").write_text(json.dumps({
        "run_id": "20260421-y",
        "story_state": "PLANNING",
        "requirement": "demo",
        "handoff": {"chain": []},
    }))
    (forge / "runs" / "20260421-y" / "handoffs").mkdir(parents=True)
    monkeypatch.chdir(tmp_path)
    rc = cli_main(["write", "--level", "manual"])
    assert rc == 0
    files = list((forge / "runs" / "20260421-y" / "handoffs").glob("*.md"))
    assert len(files) == 1


def test_list_shows_chain(tmp_path, monkeypatch, capsys):
    forge = tmp_path / ".forge"
    forge.mkdir()
    (forge / "state.json").write_text(json.dumps({
        "run_id": "20260421-y",
        "story_state": "A",
        "requirement": "demo",
        "handoff": {"chain": ["a.md", "b.md"]},
    }))
    (forge / "runs" / "20260421-y" / "handoffs").mkdir(parents=True)
    monkeypatch.chdir(tmp_path)
    rc = cli_main(["list"])
    assert rc == 0
    captured = capsys.readouterr()
    assert "a.md" in captured.out and "b.md" in captured.out


def test_show_latest(tmp_path, monkeypatch, capsys):
    forge = tmp_path / ".forge"
    handoff_dir = forge / "runs" / "20260421-y" / "handoffs"
    handoff_dir.mkdir(parents=True)
    (handoff_dir / "2026-04-21-143022-manual-demo.md").write_text("HANDOFF-A")
    (handoff_dir / "2026-04-21-144000-manual-demo.md").write_text("HANDOFF-B")
    (forge / "state.json").write_text(json.dumps({"run_id": "20260421-y", "handoff": {"chain": []}}))
    monkeypatch.chdir(tmp_path)
    rc = cli_main(["show", "latest"])
    assert rc == 0
    captured = capsys.readouterr()
    assert "HANDOFF-B" in captured.out
