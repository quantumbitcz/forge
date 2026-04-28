"""Every trends.jsonl line validates against trends_line.schema.json."""
from __future__ import annotations
import json
from pathlib import Path
from datetime import date
from jsonschema import Draft202012Validator
from tests.evals.benchmark.aggregate import aggregate_week, append_trends

SCHEMA = json.loads((Path(__file__).resolve().parents[2] / "tests" / "evals" / "benchmark" / "schemas" / "trends_line.schema.json").read_text())
V = Draft202012Validator(SCHEMA)


def test_append_preserves_order(tmp_path: Path) -> None:
    trends = tmp_path / "trends.jsonl"
    (tmp_path / "results").mkdir()
    line1 = aggregate_week(results_root=tmp_path / "results",
                           week_of=date(2026, 4, 20), commit_sha="a", forge_version="6.0.0",
                           hook_failures_total=0)
    line2 = aggregate_week(results_root=tmp_path / "results",
                           week_of=date(2026, 4, 27), commit_sha="b", forge_version="6.0.0",
                           hook_failures_total=1)
    append_trends(trends, line1)
    append_trends(trends, line2)
    lines = trends.read_text(encoding="utf-8").splitlines()
    assert len(lines) == 2
    p1, p2 = json.loads(lines[0]), json.loads(lines[1])
    V.validate(p1); V.validate(p2)
    assert p1["week_of"] == "2026-04-20"
    assert p2["week_of"] == "2026-04-27"
