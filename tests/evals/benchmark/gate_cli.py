"""CLI: run the regression gate against the latest trends line."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from tests.evals.benchmark.gate import evaluate_gate


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--trends", type=Path, required=True)
    p.add_argument("--baseline", type=Path, required=True)
    args = p.parse_args(argv)
    if not args.trends.is_file():
        print("no trends.jsonl; skipping gate", file=sys.stderr)
        return 0
    lines = [json.loads(line) for line in args.trends.read_text().splitlines() if line.strip()]
    if not lines:
        print("empty trends.jsonl; skipping gate", file=sys.stderr)
        return 0
    baseline = json.loads(args.baseline.read_text()) if args.baseline.is_file() else None
    result = evaluate_gate(current=lines[-1], baseline=baseline)
    for f in result.findings:
        print(f"[{f.severity}] {f.category}: {f.message}", file=sys.stderr)
    return 0 if result.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
