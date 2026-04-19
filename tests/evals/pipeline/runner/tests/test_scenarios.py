"""Tests for scenario discovery."""
from __future__ import annotations

from pathlib import Path

import pytest

from tests.evals.pipeline.runner.scenarios import (
    ScenarioCollectionError,
    discover_scenarios,
)


def _write_scenario(root: Path, sid: str, yaml_body: str, prompt: str = "Do the thing.") -> None:
    d = root / sid
    d.mkdir(parents=True)
    (d / "prompt.md").write_text(prompt, encoding="utf-8")
    (d / "expected.yaml").write_text(yaml_body, encoding="utf-8")


VALID_YAML = """
id: 01-test
mode: standard
token_budget: 1000
elapsed_budget_seconds: 60
min_pipeline_score: 70
required_verdict: PASS
touched_files_expected:
  - src/a.py
must_not_touch:
  - .claude/**
notes: ""
"""


def test_discover_scenarios_returns_sorted_list(tmp_path: Path) -> None:
    _write_scenario(tmp_path, "02-b", VALID_YAML.replace("01-test", "02-b"))
    _write_scenario(tmp_path, "01-a", VALID_YAML.replace("01-test", "01-a"))
    found = discover_scenarios(tmp_path)
    assert [s.id for s in found] == ["01-a", "02-b"]


def test_discover_scenarios_fail_fast_on_bad_yaml(tmp_path: Path) -> None:
    _write_scenario(tmp_path, "01-ok", VALID_YAML.replace("01-test", "01-ok"))
    _write_scenario(tmp_path, "02-bad", "mode: bogus\n")
    with pytest.raises(ScenarioCollectionError) as excinfo:
        discover_scenarios(tmp_path)
    assert "02-bad" in str(excinfo.value)


def test_discover_scenarios_rejects_id_mismatch(tmp_path: Path) -> None:
    # expected.yaml id differs from directory name → fail
    _write_scenario(tmp_path, "01-dir", VALID_YAML.replace("01-test", "99-yaml"))
    with pytest.raises(ScenarioCollectionError) as excinfo:
        discover_scenarios(tmp_path)
    assert "id mismatch" in str(excinfo.value).lower()


def test_discover_scenarios_requires_prompt_md(tmp_path: Path) -> None:
    d = tmp_path / "01-no-prompt"
    d.mkdir()
    (d / "expected.yaml").write_text(VALID_YAML.replace("01-test", "01-no-prompt"))
    with pytest.raises(ScenarioCollectionError):
        discover_scenarios(tmp_path)


def test_discover_scenarios_empty_root_returns_empty(tmp_path: Path) -> None:
    assert discover_scenarios(tmp_path) == []
