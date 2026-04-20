"""state_write -> OTel span attribute mirror (Task 8).

Verifies emit_event_mirror sets event keys (minus ``type``) as attributes on
the active span, and that state_write.append_event invokes the mirror.
"""
from __future__ import annotations

import json

import pytest

pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import (
    InMemorySpanExporter,
)

from hooks._py import otel, state_write


def _enable(monkeypatch):
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(
        otel,
        "_build_processor",
        lambda cfg: SimpleSpanProcessor(exporter),
        raising=False,
    )
    otel.init(
        {
            "enabled": True,
            "sample_rate": 1.0,
            "exporter": "console",
            "endpoint": "",
            "batch_size": 1,
            "flush_interval_seconds": 1,
            "service_name": "forge-pipeline",
        }
    )
    return exporter


def test_emit_event_mirror_applies_attrs_to_active_span(monkeypatch):
    exporter = _enable(monkeypatch)
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.stage_span("EXPLORING"):
            otel.emit_event_mirror(
                {
                    "type": "stage.progress",
                    "forge.score": 85,
                    "forge.phase_iterations": 3,
                }
            )
    otel.shutdown()
    stage = next(
        s
        for s in exporter.get_finished_spans()
        if s.name == "stage.EXPLORING"
    )
    assert stage.attributes["forge.score"] == 85
    assert stage.attributes["forge.phase_iterations"] == 3
    # 'type' is stripped (it duplicates the span name).
    assert "type" not in stage.attributes


def test_emit_event_mirror_disabled_is_noop():
    """When OTel is disabled, the mirror must not raise."""
    otel.init({"enabled": False})
    otel.emit_event_mirror({"type": "x", "k": 1})  # no-op, no exception


def test_emit_event_mirror_swallows_attribute_errors(monkeypatch):
    """Bad attribute values should never bubble up and crash state writes."""
    exporter = _enable(monkeypatch)
    with otel.pipeline_span(run_id="r1", mode="standard"):
        # Lists of dicts are not valid OTel attribute types.
        otel.emit_event_mirror(
            {"type": "ev", "valid_int": 7, "invalid_value": [{"a": 1}]}
        )
    otel.shutdown()
    p = next(s for s in exporter.get_finished_spans() if s.name == "pipeline")
    # Valid keys still applied; invalid ones silently dropped.
    assert p.attributes["valid_int"] == 7


def test_state_write_append_event_calls_mirror(monkeypatch, tmp_path):
    """append_event() must invoke otel.emit_event_mirror after writing."""
    exporter = _enable(monkeypatch)
    captured: list[dict] = []

    real_mirror = otel.emit_event_mirror

    def _spy(event: dict) -> None:
        captured.append(dict(event))
        real_mirror(event)

    monkeypatch.setattr(otel, "emit_event_mirror", _spy)
    log_path = tmp_path / "events.jsonl"
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.stage_span("EXPLORING"):
            state_write.append_event(
                log_path,
                {
                    "type": "stage.progress",
                    "forge.score": 90,
                    "forge.phase_iterations": 1,
                },
            )
    otel.shutdown()

    # File contains exactly one JSON line with the event.
    rows = [
        json.loads(line)
        for line in log_path.read_text().splitlines()
        if line.strip()
    ]
    assert rows == [
        {
            "type": "stage.progress",
            "forge.score": 90,
            "forge.phase_iterations": 1,
        }
    ]
    # Mirror was invoked exactly once with the same event.
    assert captured == rows
    # The active span received the mirrored attributes.
    stage = next(
        s
        for s in exporter.get_finished_spans()
        if s.name == "stage.EXPLORING"
    )
    assert stage.attributes["forge.score"] == 90


def test_state_write_append_event_survives_mirror_failure(
    monkeypatch, tmp_path
):
    """If emit_event_mirror raises, append_event must NOT propagate."""
    log_path = tmp_path / "events.jsonl"

    def _boom(event: dict) -> None:
        raise RuntimeError("mirror exploded")

    monkeypatch.setattr(otel, "emit_event_mirror", _boom)
    # Must not raise.
    state_write.append_event(log_path, {"type": "ok", "a": 1})
    rows = [
        json.loads(line)
        for line in log_path.read_text().splitlines()
        if line.strip()
    ]
    assert rows == [{"type": "ok", "a": 1}]
