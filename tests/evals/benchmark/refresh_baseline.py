"""Freeze or refresh tests/evals/benchmark/baseline.json from latest trends line."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m tests.evals.benchmark.refresh_baseline")
    p.add_argument("--trends", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--commit-sha", type=str, default="local")
    p.add_argument("--confirm", action="store_true")
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if not args.confirm:
        print("refuse: --confirm is required (baseline refresh is destructive)", file=sys.stderr)
        return 2

    lines = [
        json.loads(line)
        for line in args.trends.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    if not lines:
        print("error: trends file is empty", file=sys.stderr)
        return 1
    latest = lines[-1]

    baselines: dict[str, dict[str, float]] = {}
    for c in latest["cells"]:
        m = c["model"]
        b = baselines.setdefault(m, {"S": 0.0, "M": 0.0, "L": 0.0, "overall": 0.0})
        by = c["solve_rate_by_complexity"]
        b["S"] = by.get("S", 0.0)
        b["M"] = by.get("M", 0.0)
        b["L"] = by.get("L", 0.0)
        b["overall"] = c["solve_rate_overall"]

    doc = {
        "schema_version": 1,
        "frozen_on": date.today().isoformat(),
        "frozen_commit_sha": args.commit_sha,
        "baselines": baselines,
        "regression_threshold_pp": 10,
    }
    args.output.write_text(json.dumps(doc, indent=2, sort_keys=True), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
