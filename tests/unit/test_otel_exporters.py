import pytest

pytest.importorskip("opentelemetry.exporter.otlp.proto.grpc.trace_exporter")

from hooks._py.otel_exporters import build_exporter  # noqa: E402


def test_grpc_exporter():
    e = build_exporter(kind="grpc", endpoint="http://localhost:4317")
    assert type(e).__name__ == "OTLPSpanExporter"


def test_http_exporter():
    e = build_exporter(kind="http", endpoint="http://localhost:4318/v1/traces")
    assert type(e).__name__ == "OTLPSpanExporter"


def test_console_exporter():
    e = build_exporter(kind="console", endpoint="")
    assert type(e).__name__ == "ConsoleSpanExporter"


def test_unknown_exporter_raises():
    with pytest.raises(ValueError, match="exporter"):
        build_exporter(kind="kafka", endpoint="")
