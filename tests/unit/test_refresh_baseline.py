"""refresh_baseline.py refuses without --confirm; round-trips a trends line."""
from __future__ import annotations
import json
import subprocess
import sys
from pathlib import Path
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = Draft202012Validator(json.loads((ROOT / "tests/evals/benchmark/schemas/baseline.schema.json").read_text()))


def _seed_trends(trends: Path) -> None:
    line = {"schema_version": 1, "week_of": "2026-04-27", "commit_sha": "abc",
            "forge_version": "6.0.0",
            "cells": [{"os": "ubuntu-latest", "model": "claude-sonnet-4-6",
                       "entries_total": 10, "entries_solved": 8, "entries_timeout": 0,
                       "entries_docker_skipped": 0, "solve_rate_overall": 0.8,
                       "solve_rate_by_complexity": {"S": 0.9, "M": 0.8, "L": 0.5},
                       "median_cost_per_solve_usd": 0.4, "total_cost_usd": 4.0}],
            "hook_failures_total": 0, "regressions": []}
    trends.write_text(json.dumps(line) + "\n")


def test_refuses_without_confirm(tmp_path: Path) -> None:
    trends = tmp_path / "trends.jsonl"; _seed_trends(trends)
    out = tmp_path / "baseline.json"
    r = subprocess.run([sys.executable, "-m", "tests.evals.benchmark.refresh_baseline",
                        "--trends", str(trends), "--output", str(out)],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode != 0
    assert "--confirm" in r.stderr or "--confirm" in r.stdout
    assert not out.exists()


def test_confirmed_writes_valid(tmp_path: Path) -> None:
    trends = tmp_path / "trends.jsonl"; _seed_trends(trends)
    out = tmp_path / "baseline.json"
    r = subprocess.run([sys.executable, "-m", "tests.evals.benchmark.refresh_baseline",
                        "--trends", str(trends), "--output", str(out), "--confirm", "--commit-sha", "abc"],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    doc = json.loads(out.read_text())
    SCHEMA.validate(doc)
    assert "claude-sonnet-4-6" in doc["baselines"]
    assert doc["baselines"]["claude-sonnet-4-6"]["overall"] == 0.8
