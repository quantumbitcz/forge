"""Canonical eval driver -- emits one span of every kind via OTel.

Used by `.github/workflows/otel.yml` to validate end-to-end span
shape against the pinned semconv schema. Kept intentionally tiny: the
goal is to exercise pipeline/stage/agent/tool spans and flush to the
collector so the file exporter can dump them to `/tmp/otel-out.jsonl`.
"""
from __future__ import annotations

import argparse
import os

from hooks._py import otel


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--otel-enabled", action="store_true")
    parser.add_argument("--collector-url", default="http://localhost:4317")
    args = parser.parse_args()

    if not args.otel_enabled:
        return 0

    otel.init(
        {
            "enabled": True,
            "exporter": os.environ.get("FORGE_OTEL_EXPORTER", "grpc"),
            "endpoint": args.collector_url,
            "service_name": "forge-pipeline",
            "sample_rate": 1.0,
            "batch_size": 1,
            "flush_interval_seconds": 1,
            "openinference_compat": False,
        }
    )

    with otel.pipeline_span(run_id="phase01-eval", mode="standard"):
        with otel.stage_span("EXPLORING"):
            with otel.agent_span(
                name="fg-200-planner",
                model="claude-sonnet-4-7",
                description="Canonical planner span for eval",
            ):
                otel.record_agent_result(
                    {
                        "tokens_input": 10,
                        "tokens_output": 20,
                        "cost_usd": 0.001,
                        "tool_calls": 1,
                    }
                )
                with otel.tool_span(name="Read", call_id="call-001"):
                    pass

    otel.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
