"""Cost ceiling: aggregator aborts remaining cells when cumulative spend ≥ max_weekly_cost_usd."""

from __future__ import annotations

import json
from pathlib import Path

from tests.evals.benchmark.cost_guard import CostGuard


def _spend_line(cost: float) -> dict:
    return {"estimated_cost_usd": cost, "ts": "2026-04-27T06:00:00Z"}


def test_below_ceiling(tmp_path: Path) -> None:
    g = CostGuard(max_weekly_cost_usd=200.0)
    g.record(50.0)
    g.record(40.0)
    assert g.total_usd == 90.0
    assert g.within_limit() is True


def test_exactly_at_ceiling_trips(tmp_path: Path) -> None:
    g = CostGuard(max_weekly_cost_usd=100.0)
    g.record(100.0)
    assert g.within_limit() is False


def test_simulator_feed(tmp_path: Path) -> None:
    """Feed synthetic spend events, assert abort after cumulative crosses ceiling."""
    tracker = tmp_path / "token-events.jsonl"
    with tracker.open("w") as f:
        for cost in [25.0, 30.0, 40.0, 60.0, 55.0]:
            f.write(json.dumps(_spend_line(cost)) + "\n")
    g = CostGuard(max_weekly_cost_usd=150.0)
    tripped_at = None
    for i, raw in enumerate(tracker.read_text().splitlines(), 1):
        g.record(json.loads(raw)["estimated_cost_usd"])
        if not g.within_limit():
            tripped_at = i
            break
    assert tripped_at == 4  # 25+30+40+60 = 155 ≥ 150
