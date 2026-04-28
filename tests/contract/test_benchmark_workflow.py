"""Workflow shape: cron, dispatch, matrix (3×2), required steps."""
from __future__ import annotations
from pathlib import Path
import yaml

WF = Path(__file__).resolve().parents[2] / ".github" / "workflows" / "benchmark.yml"


def test_workflow_exists() -> None:
    assert WF.is_file()


def test_cron_trigger() -> None:
    doc = yaml.safe_load(WF.read_text())
    triggers = doc[True] if True in doc else doc["on"]  # PyYAML treats `on:` as True
    assert "schedule" in triggers
    assert triggers["schedule"][0]["cron"] == "0 6 * * 1"
    assert "workflow_dispatch" in triggers


def test_matrix_has_six_cells() -> None:
    doc = yaml.safe_load(WF.read_text())
    job = doc["jobs"]["benchmark-matrix"]
    matrix = job["strategy"]["matrix"]
    assert set(matrix["os"]) == {"ubuntu-latest", "macos-latest", "windows-latest"}
    assert set(matrix["claude-model"]) == {"claude-sonnet-4-6", "claude-opus-4-7"}


def test_timeout_cap() -> None:
    doc = yaml.safe_load(WF.read_text())
    assert doc["jobs"]["benchmark-matrix"]["timeout-minutes"] == 180


def test_corpus_gate_env_only_on_cron() -> None:
    """PHASE_8_CORPUS_GATE must be set to '1' only for scheduled runs."""
    doc = yaml.safe_load(WF.read_text())
    matrix_env = doc["jobs"]["benchmark-matrix"]["env"]
    aggregate_env = doc["jobs"]["aggregate"]["env"]
    for env in (matrix_env, aggregate_env):
        gate = env["PHASE_8_CORPUS_GATE"]
        assert "github.event_name" in gate and "schedule" in gate
        # The expression must fall back to '0' (not absent) so the skipif checks
        # see a concrete value.
        assert "'0'" in gate
