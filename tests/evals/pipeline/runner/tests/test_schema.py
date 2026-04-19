"""Tests for pydantic models in runner.schema."""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from tests.evals.pipeline.runner.schema import Expected, Result, Scenario


def test_expected_parses_minimal_valid_yaml():
    data = {
        "id": "01-ts-microservice-greenfield",
        "mode": "standard",
        "token_budget": 150000,
        "elapsed_budget_seconds": 600,
        "min_pipeline_score": 85,
        "required_verdict": "PASS",
        "touched_files_expected": ["src/server.ts"],
        "must_not_touch": [".claude/**"],
        "notes": "test",
    }
    e = Expected(**data)
    assert e.id == "01-ts-microservice-greenfield"
    assert e.mode == "standard"
    assert e.touched_files_expected == ["src/server.ts"]


def test_expected_rejects_unknown_mode():
    data = {
        "id": "x",
        "mode": "bogus",
        "token_budget": 1,
        "elapsed_budget_seconds": 1,
        "min_pipeline_score": 0,
        "required_verdict": "PASS",
        "touched_files_expected": [],
        "must_not_touch": [],
        "notes": "",
    }
    with pytest.raises(ValidationError):
        Expected(**data)


def test_expected_rejects_unknown_verdict():
    data = {
        "id": "x",
        "mode": "standard",
        "token_budget": 1,
        "elapsed_budget_seconds": 1,
        "min_pipeline_score": 0,
        "required_verdict": "FAIL",
        "touched_files_expected": [],
        "must_not_touch": [],
        "notes": "",
    }
    with pytest.raises(ValidationError):
        Expected(**data)


def test_expected_rejects_negative_budget():
    data = {
        "id": "x",
        "mode": "standard",
        "token_budget": -1,
        "elapsed_budget_seconds": 1,
        "min_pipeline_score": 0,
        "required_verdict": "PASS",
        "touched_files_expected": [],
        "must_not_touch": [],
        "notes": "",
    }
    with pytest.raises(ValidationError):
        Expected(**data)


def test_scenario_requires_prompt_and_expected():
    e = Expected(
        id="x",
        mode="standard",
        token_budget=1,
        elapsed_budget_seconds=1,
        min_pipeline_score=0,
        required_verdict="PASS",
        touched_files_expected=[],
        must_not_touch=[],
        notes="",
    )
    s = Scenario(id="x", path="/tmp/x", prompt="do thing", expected=e)
    assert s.prompt == "do thing"


def test_result_serializes_to_jsonl_record():
    r = Result(
        scenario_id="01-ts-microservice-greenfield",
        started_at="2026-04-19T12:00:00Z",
        ended_at="2026-04-19T12:10:00Z",
        actual_tokens=120000,
        actual_elapsed_seconds=580,
        pipeline_score=88.0,
        verdict="PASS",
        touched_files_actual=["src/server.ts"],
        overlap_jaccard=1.0,
        token_adherence=1.0,
        elapsed_adherence=1.0,
        composite=94.0,
        findings=[],
        status="completed",
    )
    d = r.model_dump()
    assert d["scenario_id"] == "01-ts-microservice-greenfield"
    assert d["composite"] == 94.0
    assert d["status"] == "completed"


def test_result_allows_dry_run_status():
    r = Result(
        scenario_id="x",
        started_at="2026-04-19T12:00:00Z",
        ended_at="2026-04-19T12:00:05Z",
        actual_tokens=0,
        actual_elapsed_seconds=0,
        pipeline_score=0.0,
        verdict="DRY_RUN",
        touched_files_actual=[],
        overlap_jaccard=0.0,
        token_adherence=0.0,
        elapsed_adherence=0.0,
        composite=0.0,
        findings=[],
        status="dry_run",
    )
    assert r.status == "dry_run"
