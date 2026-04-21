"""Unit tests for the 4 ported audit scripts.

Covers:
  - shared.validate_finding
  - shared.generate_conventions_index
  - shared.context_guard
  - shared.cost_alerting
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]


def _run(module: str, args: list[str], cwd: Path | None = None,
         stdin: str | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(REPO) + os.pathsep + env.get("PYTHONPATH", "")
    return subprocess.run(
        [sys.executable, "-m", module, *args],
        cwd=cwd or REPO,
        env=env,
        input=stdin,
        capture_output=True,
        text=True,
        check=False,
    )


# ─────────────────────── validate_finding ─────────────────────────────────


class TestValidateFinding:
    def test_valid_5_fields(self):
        line = "src/foo.py:42 | SEC-001 | CRITICAL | hardcoded secret | rotate key"
        result = _run("shared.validate_finding", [line])
        assert result.returncode == 0

    def test_valid_6_fields_with_confidence(self):
        line = "src/foo.py:42 | SEC-001 | CRITICAL | msg | hint | confidence:HIGH"
        result = _run("shared.validate_finding", [line])
        assert result.returncode == 0

    def test_empty_line_rejected(self):
        result = _run("shared.validate_finding", [""])
        assert result.returncode == 1

    def test_too_few_fields(self):
        result = _run("shared.validate_finding", ["a | b | c"])
        assert result.returncode == 1
        assert "expected 5 or 6 fields" in result.stderr

    def test_invalid_file_line(self):
        line = "src/foo.py | SEC-001 | CRITICAL | msg | hint"
        result = _run("shared.validate_finding", [line])
        assert result.returncode == 1
        assert "file:line" in result.stderr

    def test_invalid_category(self):
        line = "src/foo.py:42 | sec-001 | CRITICAL | msg | hint"
        result = _run("shared.validate_finding", [line])
        assert result.returncode == 1
        assert "CATEGORY-CODE" in result.stderr

    def test_invalid_severity(self):
        line = "src/foo.py:42 | SEC-001 | URGENT | msg | hint"
        result = _run("shared.validate_finding", [line])
        assert result.returncode == 1
        assert "SEVERITY" in result.stderr

    def test_invalid_confidence(self):
        line = "src/foo.py:42 | SEC-001 | CRITICAL | msg | hint | conf:HIGH"
        result = _run("shared.validate_finding", [line])
        assert result.returncode == 1

    def test_reads_stdin(self):
        line = "src/foo.py:42 | SEC-001 | INFO | msg | hint"
        result = _run("shared.validate_finding", [], stdin=line + "\n")
        assert result.returncode == 0


# ─────────────────────── generate_conventions_index ───────────────────────


class TestGenerateConventionsIndex:
    def test_runs_against_repo(self, tmp_path):
        # Run in a copy of the plugin layout so we don't clobber the real index.
        # Easiest: just run it against the repo and verify exit + file write.
        # We restore the original after.
        index = REPO / "shared" / "conventions-index.md"
        original = index.read_text(encoding="utf-8") if index.exists() else None

        try:
            result = _run("shared.generate_conventions_index", [])
            assert result.returncode == 0
            assert index.exists()
            content = index.read_text(encoding="utf-8")
            assert "# Conventions Index" in content
            assert "## Error Handling" in content
        finally:
            if original is not None:
                index.write_text(original, encoding="utf-8")


# ─────────────────────── context_guard ───────────────────────────────────


def _make_state(forge_dir: Path, **overrides: object) -> None:
    forge_dir.mkdir(parents=True, exist_ok=True)
    state = {
        "_seq": 1,
        "story_state": "planning",
        "tokens": {
            "estimated_total": 0,
            "budget_ceiling": 2_000_000,
            "by_stage": {},
            "by_agent": {},
        },
    }
    state.update(overrides)
    (forge_dir / "state.json").write_text(json.dumps(state), encoding="utf-8")


class TestContextGuard:
    def test_no_state_returns_ok(self, tmp_path):
        result = _run("shared.context_guard", ["check", "10000",
                                                "--forge-dir", str(tmp_path / ".forge")])
        assert result.returncode == 0
        assert "no state.json" in result.stdout

    def test_below_threshold(self, tmp_path):
        _make_state(tmp_path / ".forge")
        result = _run("shared.context_guard", ["check", "10000",
                                                "--forge-dir", str(tmp_path / ".forge")])
        assert result.returncode == 0
        assert "OK" in result.stdout

    def test_at_condensation_threshold_returns_1(self, tmp_path):
        _make_state(tmp_path / ".forge")
        result = _run("shared.context_guard", ["check", "30000",
                                                "--forge-dir", str(tmp_path / ".forge")])
        assert result.returncode == 1
        assert "CONDENSED" in result.stdout

    def test_at_critical_threshold_returns_1(self, tmp_path):
        _make_state(tmp_path / ".forge")
        result = _run("shared.context_guard", ["check", "55000",
                                                "--forge-dir", str(tmp_path / ".forge")])
        assert result.returncode == 1
        assert "CONDENSED" in result.stdout

    def test_metrics_outputs_keys(self, tmp_path):
        forge_dir = tmp_path / ".forge"
        _make_state(forge_dir)
        # First, do a check to populate metrics
        _run("shared.context_guard", ["check", "10000", "--forge-dir", str(forge_dir)])
        result = _run("shared.context_guard", ["metrics", "--forge-dir", str(forge_dir)])
        assert result.returncode == 0
        assert "peak_tokens" in result.stdout
        assert "guard_checks" in result.stdout

    def test_metrics_no_state(self, tmp_path):
        result = _run("shared.context_guard", ["metrics",
                                                "--forge-dir", str(tmp_path / ".forge")])
        assert result.returncode == 0
        assert "No context metrics" in result.stdout


# ─────────────────────── cost_alerting ───────────────────────────────────


class TestCostAlerting:
    def test_init_creates_section(self, tmp_path):
        forge_dir = tmp_path / ".forge"
        _make_state(forge_dir)
        result = _run("shared.cost_alerting", ["init", "--forge-dir", str(forge_dir)])
        assert result.returncode == 0, result.stderr
        state = json.loads((forge_dir / "state.json").read_text())
        assert state["cost_alerting"]["enabled"] is True
        assert state["cost_alerting"]["thresholds"] == [0.50, 0.75, 0.90]
        assert "implementing" in state["cost_alerting"]["per_stage_limits"]

    def test_check_no_state(self, tmp_path):
        result = _run("shared.cost_alerting", ["check",
                                                "--forge-dir", str(tmp_path / ".forge")])
        assert result.returncode == 0

    def test_check_below_threshold(self, tmp_path):
        forge_dir = tmp_path / ".forge"
        _make_state(forge_dir, tokens={"estimated_total": 100_000,
                                       "budget_ceiling": 2_000_000, "by_stage": {}, "by_agent": {}})
        _run("shared.cost_alerting", ["init", "--forge-dir", str(forge_dir)])
        result = _run("shared.cost_alerting", ["check", "--forge-dir", str(forge_dir)])
        assert result.returncode == 0
        assert "OK" in result.stdout

    @pytest.mark.parametrize("usage,expected_code,expected_level", [
        (1_100_000, 1, "INFO"),       # 55% — past 50%
        (1_600_000, 2, "WARNING"),    # 80% — past 75%
        (1_850_000, 3, "CRITICAL"),   # 92.5% — past 90%
        (2_100_000, 4, "EXCEEDED"),   # over budget
    ])
    def test_check_thresholds(self, tmp_path, usage, expected_code, expected_level):
        forge_dir = tmp_path / ".forge"
        _make_state(forge_dir, tokens={"estimated_total": usage,
                                       "budget_ceiling": 2_000_000, "by_stage": {}, "by_agent": {}})
        _run("shared.cost_alerting", ["init", "--forge-dir", str(forge_dir)])
        result = _run("shared.cost_alerting", ["check", "--forge-dir", str(forge_dir)])
        assert result.returncode == expected_code
        assert expected_level in result.stdout
        assert "NEW_ALERT" in result.stdout

    def test_check_alert_only_emitted_once(self, tmp_path):
        forge_dir = tmp_path / ".forge"
        _make_state(forge_dir, tokens={"estimated_total": 1_100_000,
                                       "budget_ceiling": 2_000_000, "by_stage": {}, "by_agent": {}})
        _run("shared.cost_alerting", ["init", "--forge-dir", str(forge_dir)])
        first = _run("shared.cost_alerting", ["check", "--forge-dir", str(forge_dir)])
        second = _run("shared.cost_alerting", ["check", "--forge-dir", str(forge_dir)])
        assert "NEW_ALERT" in first.stdout
        assert "NEW_ALERT" not in second.stdout

    def test_summary(self, tmp_path):
        forge_dir = tmp_path / ".forge"
        _make_state(forge_dir, tokens={"estimated_total": 500_000,
                                       "budget_ceiling": 2_000_000,
                                       "by_stage": {"planning": {"input": 100, "output": 50}},
                                       "by_agent": {}})
        result = _run("shared.cost_alerting", ["summary", "--forge-dir", str(forge_dir)])
        assert result.returncode == 0
        assert "Budget:" in result.stdout
        assert "Per-stage:" in result.stdout
        assert "planning" in result.stdout

    def test_stage_report(self, tmp_path):
        forge_dir = tmp_path / ".forge"
        _make_state(forge_dir, tokens={"estimated_total": 500_000,
                                       "budget_ceiling": 2_000_000,
                                       "by_stage": {"implementing": {"input": 50_000, "output": 50_000}},
                                       "by_agent": {}})
        result = _run("shared.cost_alerting",
                      ["stage-report", "implementing", "--forge-dir", str(forge_dir)])
        assert result.returncode == 0
        assert "[COST] IMPL" in result.stdout

    def test_apply_downgrade(self, tmp_path):
        forge_dir = tmp_path / ".forge"
        _make_state(forge_dir)
        result = _run("shared.cost_alerting",
                      ["apply-downgrade", "--forge-dir", str(forge_dir)])
        assert result.returncode == 0
        state = json.loads((forge_dir / "state.json").read_text())
        assert state["cost_alerting"]["routing_override"]["fg-200-planner"] == "sonnet"
