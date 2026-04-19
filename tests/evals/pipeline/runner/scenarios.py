"""Scenario discovery and schema validation.

Fail-fast collection: every scenario is parsed at the start of a run; any
malformed ``expected.yaml`` aborts the whole run before a single forge
invocation happens.
"""
from __future__ import annotations

from pathlib import Path

import yaml
from pydantic import ValidationError

from tests.evals.pipeline.runner.schema import Expected, Scenario


class ScenarioCollectionError(Exception):
    """Raised when a scenario directory is malformed. Halts the run."""


def discover_scenarios(root: Path) -> list[Scenario]:
    """Enumerate ``<root>/*/expected.yaml``, parse, validate, return sorted by id.

    Raises ScenarioCollectionError on the first malformed scenario; callers
    should treat this as fatal.
    """
    scenarios: list[Scenario] = []
    if not root.exists():
        return scenarios

    for child in sorted(p for p in root.iterdir() if p.is_dir()):
        expected_path = child / "expected.yaml"
        prompt_path = child / "prompt.md"

        if not expected_path.is_file():
            raise ScenarioCollectionError(
                f"{child.name}: missing expected.yaml at {expected_path}"
            )
        if not prompt_path.is_file():
            raise ScenarioCollectionError(
                f"{child.name}: missing prompt.md at {prompt_path}"
            )

        try:
            raw = yaml.safe_load(expected_path.read_text(encoding="utf-8"))
        except yaml.YAMLError as e:
            raise ScenarioCollectionError(
                f"{child.name}: YAML parse error: {e}"
            ) from e

        try:
            expected = Expected(**(raw or {}))
        except ValidationError as e:
            raise ScenarioCollectionError(
                f"{child.name}: schema validation failed: {e}"
            ) from e

        if expected.id != child.name:
            raise ScenarioCollectionError(
                f"{child.name}: id mismatch — directory is {child.name!r} "
                f"but expected.yaml says {expected.id!r}"
            )

        prompt = prompt_path.read_text(encoding="utf-8")
        scenarios.append(
            Scenario(id=child.name, path=str(child), prompt=prompt, expected=expected)
        )

    return scenarios
