from __future__ import annotations

import json
from pathlib import Path

from hooks._py import token_tracker as tt


def test_record_usage_creates_tokens_section(tmp_path: Path):
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"_seq": 0}))
    tt.record_usage(state, agent="fg-100", prompt=1000, completion=200, model="sonnet")
    data = json.loads(state.read_text())
    assert data["tokens"]["total"]["prompt"] == 1000
    assert data["tokens"]["total"]["completion"] == 200
    assert data["tokens"]["by_agent"]["fg-100"]["prompt"] == 1000


def test_record_usage_accumulates(tmp_path: Path):
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"_seq": 0}))
    tt.record_usage(state, agent="fg-200", prompt=500, completion=100, model="sonnet")
    tt.record_usage(state, agent="fg-200", prompt=300, completion=50, model="sonnet")
    data = json.loads(state.read_text())
    assert data["tokens"]["by_agent"]["fg-200"]["prompt"] == 800
    assert data["tokens"]["by_agent"]["fg-200"]["completion"] == 150


def test_estimate_cost_usd_sonnet():
    # Sonnet 3.5 pricing (per doc): $3/M input, $15/M output.
    cost = tt.estimate_cost_usd(prompt=1_000_000, completion=1_000_000, model="sonnet")
    assert cost == 18.0


def test_estimate_cost_usd_unknown_model_returns_zero():
    assert tt.estimate_cost_usd(prompt=1_000_000, completion=1_000_000, model="???") == 0.0


def test_ceiling_exceeded_reports_true(tmp_path: Path):
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"_seq": 0}))
    tt.record_usage(state, agent="fg-100", prompt=5_000_000, completion=1_000_000, model="sonnet")
    assert tt.ceiling_exceeded(state, max_usd=10.0) is True
