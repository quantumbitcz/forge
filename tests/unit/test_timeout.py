from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from hooks._py import timeout


def _write_state(path: Path, *, preflight_iso: str):
    path.write_text(json.dumps({"stage_timestamps": {"preflight": preflight_iso}}))


def test_within_budget_returns_ok(tmp_path: Path):
    state = tmp_path / "state.json"
    _write_state(state, preflight_iso=datetime.now(timezone.utc).isoformat())
    result = timeout.check(state, max_seconds=3600)
    assert result.exceeded is False
    assert result.warning is False


def test_at_80_percent_warns(tmp_path: Path):
    state = tmp_path / "state.json"
    start = datetime.now(timezone.utc) - timedelta(seconds=4900)
    _write_state(state, preflight_iso=start.isoformat())
    result = timeout.check(state, max_seconds=6000)
    assert result.exceeded is False
    assert result.warning is True


def test_exceeded_over_budget(tmp_path: Path):
    state = tmp_path / "state.json"
    start = datetime.now(timezone.utc) - timedelta(seconds=7300)
    _write_state(state, preflight_iso=start.isoformat())
    result = timeout.check(state, max_seconds=7200)
    assert result.exceeded is True


def test_missing_state_returns_ok(tmp_path: Path):
    state = tmp_path / "absent.json"
    result = timeout.check(state, max_seconds=60)
    assert result.exceeded is False
