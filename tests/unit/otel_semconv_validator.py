"""CI validator: semconv schema + tokens.total consistency + hierarchy."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable

import jsonschema

_SCHEMA = json.loads(
    (Path(__file__).parent.parent.parent / "shared" / "schemas" / "otel-genai-v1.json").read_text()
)


def validate_spans(spans: Iterable[dict]) -> list[str]:
    errors: list[str] = []
    for span in spans:
        kind = span.get("kind", "")
        attrs = span.get("attributes", {})
        if kind == "agent":
            schema = _SCHEMA["properties"]["agent_span"]
        elif kind == "tool":
            schema = _SCHEMA["properties"]["tool_span"]
        else:
            continue
        try:
            jsonschema.validate(instance=attrs, schema=schema)
        except jsonschema.ValidationError as e:
            errors.append(f"{span.get('name', '?')}: {e.message}")
        # tokens.total consistency
        if kind == "agent":
            ti = attrs.get("gen_ai.tokens.input")
            to = attrs.get("gen_ai.tokens.output")
            tt = attrs.get("gen_ai.tokens.total")
            if ti is not None and to is not None and tt is not None and ti + to != tt:
                errors.append(
                    f"{span.get('name', '?')}: gen_ai.tokens.total={tt} != input+output={ti+to}"
                )
    return errors


def validate_hierarchy(spans: list[dict]) -> list[str]:
    """Every non-root span must share the pipeline root's trace_id."""
    errors = []
    roots = [s for s in spans if s.get("name") == "pipeline"]
    if not roots:
        return ["no pipeline root span"]
    root_tid = roots[0].get("trace_id")
    for s in spans:
        if s.get("trace_id") != root_tid:
            errors.append(f"{s.get('name', '?')}: trace_id mismatch (orphan)")
    return errors
