"""OTel semconv schema + validator tests."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

pytest.importorskip("jsonschema")

SCHEMA = Path(__file__).parent.parent.parent / "shared" / "schemas" / "otel-genai-v1.json"


def test_schema_file_exists_and_is_valid_json():
    assert SCHEMA.exists(), "pinned semconv schema missing"
    data = json.loads(SCHEMA.read_text())
    assert data.get("$schema", "").startswith("https://json-schema.org/")
    assert "properties" in data
    required_attrs = data["properties"]["agent_span"]["required"]
    for a in ("gen_ai.agent.name", "gen_ai.operation.name", "gen_ai.request.model"):
        assert a in required_attrs


def test_validator_accepts_emitted_spans():
    from tests.unit.otel_semconv_validator import validate_spans

    good = [
        {
            "name": "agent.fg-200-planner",
            "attributes": {
                "gen_ai.agent.name": "fg-200-planner",
                "gen_ai.operation.name": "invoke_agent",
                "gen_ai.request.model": "claude-sonnet-4-7",
                "gen_ai.tokens.input": 10,
                "gen_ai.tokens.output": 20,
                "gen_ai.tokens.total": 30,
            },
            "kind": "agent",
        }
    ]
    errors = validate_spans(good)
    assert errors == []


def test_validator_rejects_missing_required_attribute():
    from tests.unit.otel_semconv_validator import validate_spans

    bad = [
        {
            "name": "agent.x",
            "attributes": {
                "gen_ai.agent.name": "x",
                "gen_ai.operation.name": "invoke_agent",
            },
            "kind": "agent",
        }
    ]
    errors = validate_spans(bad)
    assert any("gen_ai.request.model" in e for e in errors)


def test_validator_rejects_token_math_violation():
    from tests.unit.otel_semconv_validator import validate_spans

    bad = [
        {
            "name": "agent.x",
            "attributes": {
                "gen_ai.agent.name": "x",
                "gen_ai.operation.name": "invoke_agent",
                "gen_ai.request.model": "m",
                "gen_ai.tokens.input": 10,
                "gen_ai.tokens.output": 20,
                "gen_ai.tokens.total": 99,  # wrong
            },
            "kind": "agent",
        }
    ]
    errors = validate_spans(bad)
    assert any("tokens.total" in e for e in errors)
