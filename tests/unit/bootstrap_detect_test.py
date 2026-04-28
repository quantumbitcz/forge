# tests/unit/bootstrap_detect_test.py
"""Tests for shared/bootstrap-detect.py — stack detection + atomic-write contract.

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §2
ACs:  AC-S015, AC-S017, AC-S018, AC-S027 (atomic-write).
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "shared" / "bootstrap-detect.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("bootstrap_detect", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["bootstrap_detect"] = module
    spec.loader.exec_module(module)
    return module


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

    We simulate a mid-write interrupt by monkeypatching Path.rename to raise.
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

    original_rename = Path.rename

    def boom(self: Path, *args, **kwargs):  # type: ignore[no-untyped-def]
        raise RuntimeError("simulated interrupt during rename")

    monkeypatch.setattr(Path, "rename", boom)
    with pytest.raises(RuntimeError, match="simulated interrupt"):
        bootstrap_detect.write_forge_local_md(stack, target)

    # Target file must NOT exist after failure (atomic-write contract).
    assert not target.exists(), "target file leaked after simulated rename failure"
    # Temp file must also be cleaned up.
    monkeypatch.setattr(Path, "rename", original_rename)
    temp = target.with_suffix(target.suffix + ".tmp")
    assert not temp.exists(), "temp file leaked after simulated rename failure"


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
