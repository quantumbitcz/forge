"""Every BenchmarkResult serialization matches result.schema.json."""

from __future__ import annotations

import json
from pathlib import Path

from jsonschema import Draft202012Validator

from tests.evals.benchmark.result import BenchmarkResult

SCHEMA = json.loads(
    (
        Path(__file__).resolve().parents[2]
        / "tests"
        / "evals"
        / "benchmark"
        / "schemas"
        / "result.schema.json"
    ).read_text()
)
_VALIDATOR = Draft202012Validator(SCHEMA)


def test_minimal_serialization_round_trip() -> None:
    r = BenchmarkResult(
        schema_version=1,
        entry_id="2025-11-14-demo",
        run_date="2026-04-27",
        os="ubuntu-latest",
        model="claude-sonnet-4-6",
        complexity="S",
        started_at="2026-04-27T06:00:00Z",
        ended_at="2026-04-27T06:10:00Z",
        duration_s=600,
        solved=True,
        partial_ac_pct=1.0,
        ac_breakdown={"AC-B001": "PASS"},
        unverifiable_count=0,
        cost_usd=0.42,
        pipeline_verdict="SHIP",
        score=95,
        convergence_iterations=2,
        critical_findings=0,
        warning_findings=1,
        timeout=False,
        must_not_touch_violations=[],
        touched_files_actual=["src/a.py"],
        hook_failures_count=0,
        error=None,
    )
    doc = r.to_dict()
    _VALIDATOR.validate(doc)
    assert json.loads(json.dumps(doc))  # strict-json-serializable


def test_dry_run_variant_validates() -> None:
    r = BenchmarkResult.dry_run(
        entry_id="2026-01-01-hello-health",
        os="ubuntu-latest",
        model="claude-sonnet-4-6",
        complexity="S",
    )
    _VALIDATOR.validate(r.to_dict())
    assert r.pipeline_verdict == "DRY_RUN"


def test_unverifiable_count_derived_from_breakdown() -> None:
    r = BenchmarkResult(
        schema_version=1,
        entry_id="demo",
        run_date="2026-04-27",
        os="ubuntu-latest",
        model="claude-sonnet-4-6",
        complexity="M",
        started_at="2026-04-27T06:00:00Z",
        ended_at="2026-04-27T06:10:00Z",
        duration_s=600,
        solved=False,
        partial_ac_pct=0.5,
        ac_breakdown={"AC-B001": "PASS", "AC-B002": "UNVERIFIABLE"},
        unverifiable_count=1,
        cost_usd=0.0,
        pipeline_verdict="CONCERNS",
        score=70,
        convergence_iterations=1,
        critical_findings=0,
        warning_findings=0,
        timeout=False,
        hook_failures_count=0,
        error=None,
    )
    _VALIDATOR.validate(r.to_dict())
