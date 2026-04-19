"""Exporter factory keyed on ``config.observability.otel.exporter``."""

from __future__ import annotations

from typing import Any


def build_exporter(
    *, kind: str, endpoint: str, headers: dict[str, str] | None = None
) -> Any:
    if kind == "grpc":
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
            OTLPSpanExporter,
        )

        return OTLPSpanExporter(endpoint=endpoint, headers=headers or {})
    if kind == "http":
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
            OTLPSpanExporter,
        )

        return OTLPSpanExporter(endpoint=endpoint, headers=headers or {})
    if kind == "console":
        from opentelemetry.sdk.trace.export import ConsoleSpanExporter

        return ConsoleSpanExporter()
    raise ValueError(
        f"unknown exporter kind: {kind!r} (expected grpc|http|console)"
    )
