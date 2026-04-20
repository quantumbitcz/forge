"""forge OTel CLI.

Usage:
  python -m hooks._py.otel_cli replay --from-events <path> [options]

The ``replay`` subcommand rebuilds spans from ``.forge/events.jsonl`` and
emits them via the configured exporter. This is the AUTHORITATIVE recovery
path -- the live stream is best-effort, but the event log is fsync'd per row
(Phase F07), so replay is byte-for-byte deterministic modulo timestamps.
"""

from __future__ import annotations

import argparse
import sys

from hooks._py import otel


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="forge-otel")
    sub = parser.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("replay", help="Rebuild spans from an event log")
    r.add_argument("--from-events", required=True)
    r.add_argument(
        "--exporter", default="grpc", choices=["grpc", "http", "console"]
    )
    r.add_argument("--endpoint", default="http://localhost:4317")
    r.add_argument("--sample-rate", type=float, default=1.0)
    r.add_argument("--service-name", default="forge-pipeline")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    if args.cmd == "replay":
        n = otel.replay(
            events_path=args.from_events,
            config={
                "enabled": True,
                "exporter": args.exporter,
                "endpoint": args.endpoint,
                "sample_rate": args.sample_rate,
                "service_name": args.service_name,
                "batch_size": 32,
                "flush_interval_seconds": 2,
            },
        )
        print(f"replayed {n} spans from {args.from_events}")
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
