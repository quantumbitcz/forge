"""Phase 7 F35/F36 — OTel span emission for intent verification + voting."""

from __future__ import annotations

import pytest

pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import (
    InMemorySpanExporter,
)

from hooks._py import otel
from hooks._py import otel_attributes as A


@pytest.fixture
def exporter():
    # Replace the module's tracer with an in-memory one.
    exp = InMemorySpanExporter()
    prov = TracerProvider()
    prov.add_span_processor(SimpleSpanProcessor(exp))
    otel._STATE.enabled = True
    otel._STATE.tracer = prov.get_tracer("test")
    yield exp
    otel._STATE.enabled = False
    otel._STATE.tracer = None


def test_intent_span_attributes(exporter):
    with otel.intent_verify_ac_span("AC-003", probe_tier=2) as span:
        otel.record_intent_verdict(span, "VERIFIED", probes_issued=3, duration_ms=127)
    spans = exporter.get_finished_spans()
    assert len(spans) == 1
    s = spans[0]
    assert s.name == "forge.intent.verify_ac"
    assert s.attributes[A.INTENT_AC_ID] == "AC-003"
    assert s.attributes[A.INTENT_AC_VERDICT] == "VERIFIED"
    assert s.attributes[A.INTENT_PROBE_TIER] == 2
    assert s.attributes[A.INTENT_PROBES_ISSUED] == 3


def test_impl_vote_span_attributes(exporter):
    with otel.impl_vote_span("CreateUserUseCase", sample_id=1, trigger="risk_tag") as span:
        otel.record_vote_verdict(span, "SAME", "sha256:abc", degraded=False)
    spans = exporter.get_finished_spans()
    assert len(spans) == 1
    s = spans[0]
    assert s.name == "forge.impl.vote"
    assert s.attributes[A.IMPL_VOTE_SAMPLE_ID] == 1
    assert s.attributes[A.IMPL_VOTE_TRIGGER] == "risk_tag"
    assert s.attributes[A.IMPL_VOTE_VERDICT] == "SAME"
