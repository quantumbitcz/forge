# tests/unit/bootstrap_detect_test.py
"""Tests for shared/bootstrap-detect.py — stack detection + atomic-write contract.

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §2
ACs:  AC-S015, AC-S017, AC-S018, AC-S027 (atomic-write).
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from tests.unit.conftest import load_hyphenated_module


def _load_module():
    return load_hyphenated_module("shared/bootstrap-detect.py", "bootstrap_detect")


@pytest.fixture(scope="module")
def bootstrap_detect():
    return _load_module()


def test_detects_kotlin_spring(bootstrap_detect, tmp_path):
    (tmp_path / "build.gradle.kts").write_text(
        'plugins { id("org.springframework.boot") version "3.4.0" }\n'
    )
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["language"] == "kotlin"
    assert result["framework"] == "spring"
    assert result["build"] == "gradle"
    assert result["ambiguous"] is False


def test_detects_typescript_next(bootstrap_detect, tmp_path):
    (tmp_path / "package.json").write_text(
        json.dumps(
            {
                "name": "demo",
                "dependencies": {"next": "14.0.0", "react": "18.0.0"},
                "devDependencies": {"typescript": "5.0.0", "vitest": "1.0.0"},
            }
        )
    )
    (tmp_path / "tsconfig.json").write_text("{}")
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["language"] == "typescript"
    assert result["framework"] == "nextjs"
    assert result["testing"] == "vitest"
    assert result["ambiguous"] is False
    # tsconfig signal must not be lost when next.config is absent but 'next' dep is present.
    assert "tsconfig.json" in result["reason"]


def test_detects_python_fastapi(bootstrap_detect, tmp_path):
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "demo"\ndependencies = ["fastapi", "uvicorn", "pytest"]\n'
    )
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["language"] == "python"
    assert result["framework"] == "fastapi"
    assert result["testing"] == "pytest"
    assert result["ambiguous"] is False


def test_ambiguous_stack_rejected(bootstrap_detect, tmp_path):
    # Both Kotlin and TypeScript hits — mixed monorepo without a clear primary.
    (tmp_path / "build.gradle.kts").write_text("plugins { kotlin(\"jvm\") }")
    (tmp_path / "package.json").write_text(json.dumps({"dependencies": {"next": "14"}}))
    (tmp_path / "tsconfig.json").write_text("{}")
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["ambiguous"] is True
    assert "multiple" in result["reason"]


def test_no_recognized_stack_is_ambiguous(bootstrap_detect, tmp_path):
    # Empty directory — no manifest at all.
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["ambiguous"] is True
    assert result["language"] is None


def test_write_forge_local_md_creates_target(bootstrap_detect, tmp_path):
    target = tmp_path / ".claude" / "forge.local.md"
    stack = {
        "language": "kotlin",
        "framework": "spring",
        "testing": "junit5",
        "build": "gradle",
        "ambiguous": False,
        "reason": "build.gradle.kts present (Spring Boot detected)",
    }
    bootstrap_detect.write_forge_local_md(stack, target)
    assert target.exists()
    body = target.read_text(encoding="utf-8")
    assert "language: kotlin" in body
    assert "framework: spring" in body


def test_write_refuses_ambiguous_stack(bootstrap_detect, tmp_path):
    target = tmp_path / ".claude" / "forge.local.md"
    stack = {
        "language": None,
        "framework": None,
        "testing": None,
        "build": None,
        "ambiguous": True,
        "reason": "no recognized build manifest at repo root",
    }
    with pytest.raises(ValueError, match="ambiguous"):
        bootstrap_detect.write_forge_local_md(stack, target)
    assert not target.exists()


def test_write_is_atomic_under_simulated_interrupt(bootstrap_detect, tmp_path, monkeypatch):
    """AC-S027: target is either absent or fully written, never partial.

    We simulate a mid-write interrupt by monkeypatching Path.replace to raise.
    After the failure, the target must NOT exist — only the .tmp file may
    have been written, and our cleanup deletes it.
    """
    target = tmp_path / ".claude" / "forge.local.md"
    stack = {
        "language": "kotlin",
        "framework": "spring",
        "testing": "junit5",
        "build": "gradle",
        "ambiguous": False,
        "reason": "ok",
    }

    original_replace = Path.replace

    def boom(self: Path, *args, **kwargs):  # type: ignore[no-untyped-def]
        raise RuntimeError("simulated interrupt during replace")

    monkeypatch.setattr(Path, "replace", boom)
    with pytest.raises(RuntimeError, match="simulated interrupt"):
        bootstrap_detect.write_forge_local_md(stack, target)

    # Target file must NOT exist after failure (atomic-write contract).
    assert not target.exists(), "target file leaked after simulated replace failure"
    # Temp file must also be cleaned up.
    monkeypatch.setattr(Path, "replace", original_replace)
    temp = target.with_suffix(target.suffix + ".tmp")
    assert not temp.exists(), "temp file leaked after simulated replace failure"


def test_write_handles_disk_full_simulation(bootstrap_detect, tmp_path, monkeypatch):
    """AC-S018: a write failure aborts cleanly; target stays absent."""
    target = tmp_path / ".claude" / "forge.local.md"
    stack = {
        "language": "python",
        "framework": "fastapi",
        "testing": "pytest",
        "build": "uv",
        "ambiguous": False,
        "reason": "ok",
    }
    original_write = Path.write_text

    def fail(self: Path, *args, **kwargs):  # type: ignore[no-untyped-def]
        raise OSError(28, "No space left on device")

    monkeypatch.setattr(Path, "write_text", fail)
    with pytest.raises(OSError):
        bootstrap_detect.write_forge_local_md(stack, target)
    monkeypatch.setattr(Path, "write_text", original_write)
    assert not target.exists()


def test_write_handles_partial_write_then_failure(bootstrap_detect, tmp_path, monkeypatch):
    """AC-S018 / AC-S027 reinforcement: a partial write that subsequently fails still
    leaves no target file, and the temp file is cleaned up.

    We let write_text actually create the temp file (1 byte), then raise during
    Path.replace to simulate the "wrote-some-bytes-then-died" case.
    """
    target = tmp_path / ".claude" / "forge.local.md"
    stack = {
        "language": "python",
        "framework": "fastapi",
        "testing": "pytest",
        "build": "uv",
        "ambiguous": False,
        "reason": "ok",
    }

    original_write = Path.write_text
    call_state = {"writes": 0}

    def partial_then_keep(self: Path, *args, **kwargs):  # type: ignore[no-untyped-def]
        # First call writes a single byte (simulating disk truncation), then
        # subsequent calls go through normally (we won't hit them in this test).
        call_state["writes"] += 1
        if call_state["writes"] == 1:
            return original_write(self, "x", encoding="utf-8")
        return original_write(self, *args, **kwargs)

    def boom(self: Path, *args, **kwargs):  # type: ignore[no-untyped-def]
        raise OSError(5, "I/O error during replace")

    monkeypatch.setattr(Path, "write_text", partial_then_keep)
    monkeypatch.setattr(Path, "replace", boom)
    with pytest.raises(OSError, match="I/O error"):
        bootstrap_detect.write_forge_local_md(stack, target)

    # Target must NOT exist; temp must be cleaned up even after partial write.
    assert not target.exists()
    temp = target.with_suffix(target.suffix + ".tmp")
    assert not temp.exists(), "temp file leaked after partial-write + replace failure"


def test_typescript_detection_includes_next_config_ts(bootstrap_detect, tmp_path):
    """next.config.ts (TypeScript Next config) must be recognized."""
    (tmp_path / "package.json").write_text(json.dumps({"dependencies": {"next": "14.0.0"}}))
    (tmp_path / "next.config.ts").write_text("export default {};")
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["language"] == "typescript"
    assert result["framework"] == "nextjs"


def test_typescript_detection_includes_next_config_cjs(bootstrap_detect, tmp_path):
    """next.config.cjs (CommonJS Next config) must be recognized."""
    (tmp_path / "package.json").write_text(json.dumps({"dependencies": {"next": "14.0.0"}}))
    (tmp_path / "next.config.cjs").write_text("module.exports = {};")
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["language"] == "typescript"
    assert result["framework"] == "nextjs"


def test_python_pytest_detection_is_case_insensitive(bootstrap_detect, tmp_path):
    """pytest detection should match regardless of casing in pyproject.toml."""
    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "demo"\ndependencies = ["fastapi"]\n'
        '[tool.PyTest.ini_options]\naddopts = "-q"\n'
    )
    result = bootstrap_detect.detect_stack(tmp_path)
    assert result["testing"] == "pytest"
