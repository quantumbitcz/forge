"""Benchmark emits six span attributes per run: entry_id, os, model, solved, duration_s, cost_usd."""

from __future__ import annotations

from tests.evals.benchmark.otel_emit import emit_benchmark_span


def test_emit_span_shape(monkeypatch) -> None:
    captured = []

    def fake_replay(name, attrs):
        captured.append((name, dict(attrs)))

    monkeypatch.setattr("tests.evals.benchmark.otel_emit._replay", fake_replay)
    emit_benchmark_span(
        entry_id="2026-04-27-x",
        os="ubuntu-latest",
        model="claude-sonnet-4-6",
        solved=True,
        duration_s=600,
        cost_usd=0.42,
    )
    assert len(captured) == 1
    name, attrs = captured[0]
    assert name == "forge.benchmark.run"
    assert attrs["forge.benchmark.entry_id"] == "2026-04-27-x"
    assert attrs["forge.benchmark.os"] == "ubuntu-latest"
    assert attrs["forge.benchmark.model"] == "claude-sonnet-4-6"
    assert attrs["forge.benchmark.solved"] is True
    assert attrs["forge.benchmark.duration_s"] == 600
    assert attrs["forge.benchmark.cost_usd"] == 0.42
