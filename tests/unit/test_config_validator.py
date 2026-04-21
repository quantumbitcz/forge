"""Unit tests for shared.config_validator."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
MODULE_ARGS = [sys.executable, "-m", "shared.config_validator"]


def _run(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["PYTHONPATH"] = str(REPO) + os.pathsep + env.get("PYTHONPATH", "")
    return subprocess.run(
        MODULE_ARGS + args,
        cwd=cwd or REPO,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def _make_project(
    tmp_path: Path,
    local: str | None,
    config: str | None = None,
) -> Path:
    claude = tmp_path / ".claude"
    claude.mkdir(parents=True)
    if local is not None:
        (claude / "forge.local.md").write_text(local)
    if config is not None:
        (claude / "forge-config.md").write_text(config)
    return tmp_path


# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------


def test_missing_project_root_arg_exits_2():
    """argparse rejects missing positional with exit code 2 (its default)."""
    result = _run([])
    assert result.returncode == 2
    assert "project_root" in result.stderr


def test_missing_claude_dir_exits_3(tmp_path):
    result = _run([str(tmp_path)])
    assert result.returncode == 3
    assert ".claude/" in result.stderr


def test_missing_local_file_exits_3(tmp_path):
    (tmp_path / ".claude").mkdir()
    result = _run([str(tmp_path)])
    assert result.returncode == 3
    assert "forge.local.md" in result.stderr


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


VALID_LOCAL = textwrap.dedent("""\
    ---
    components:
      language: python
      framework: fastapi
      testing: pytest
    commands:
      build: poetry build
      test: pytest
      lint: ruff check
    ---
    """)


def test_valid_local_only_exits_0(tmp_path):
    project = _make_project(tmp_path, VALID_LOCAL)
    result = _run([str(project)])
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Configuration is valid" in result.stdout


def test_unknown_language_exits_1(tmp_path):
    bad_local = VALID_LOCAL.replace("language: python", "language: cobol")
    project = _make_project(tmp_path, bad_local)
    result = _run([str(project)])
    assert result.returncode == 1
    assert "Unknown language" in result.stdout


def test_missing_build_command_exits_1(tmp_path):
    bad_local = VALID_LOCAL.replace("build: poetry build", "build:")
    project = _make_project(tmp_path, bad_local)
    result = _run([str(project)])
    assert result.returncode == 1
    assert "build" in result.stdout


def test_k8s_framework_allows_null_language(tmp_path):
    k8s_local = textwrap.dedent("""\
        ---
        components:
          language: null
          framework: k8s
          testing: null
        commands:
          build: kubectl apply
          test: kubectl get pods
        ---
        """)
    project = _make_project(tmp_path, k8s_local)
    result = _run([str(project)])
    assert result.returncode == 0, result.stdout + result.stderr


# ---------------------------------------------------------------------------
# Range / cross-field
# ---------------------------------------------------------------------------


VALID_CONFIG = textwrap.dedent("""\
    ```yaml
    scoring:
      pass_threshold: 80
      concerns_threshold: 60
      warning_weight: 5
      info_weight: 2
    convergence:
      target_score: 90
    shipping:
      min_score: 90
    ```
    """)


def test_valid_config_passes(tmp_path):
    project = _make_project(tmp_path, VALID_LOCAL, VALID_CONFIG)
    result = _run([str(project)])
    assert result.returncode == 0, result.stdout + result.stderr


def test_pass_concerns_gap_too_small_exits_1(tmp_path):
    bad_config = VALID_CONFIG.replace("concerns_threshold: 60", "concerns_threshold: 75")
    project = _make_project(tmp_path, VALID_LOCAL, bad_config)
    result = _run([str(project)])
    assert result.returncode == 1
    assert "Gap is 5" in result.stdout


def test_target_score_below_pass_threshold_exits_1(tmp_path):
    bad_config = VALID_CONFIG.replace("target_score: 90", "target_score: 70")
    project = _make_project(tmp_path, VALID_LOCAL, bad_config)
    result = _run([str(project)])
    assert result.returncode == 1
    assert "target_score" in result.stdout


def test_unknown_top_level_field_emits_warning(tmp_path):
    weird_config = textwrap.dedent("""\
        ```yaml
        scoring:
          pass_threshold: 80
          concerns_threshold: 60
        wibble:
          foo: bar
        ```
        """)
    project = _make_project(tmp_path, VALID_LOCAL, weird_config)
    result = _run([str(project)])
    # warnings only → exit code 2
    assert result.returncode == 2
    assert "Unknown top-level field" in result.stdout
    assert "wibble" in result.stdout


# ---------------------------------------------------------------------------
# Output formats
# ---------------------------------------------------------------------------


def test_json_output_is_valid_json(tmp_path):
    project = _make_project(tmp_path, VALID_LOCAL, VALID_CONFIG)
    result = _run(["--json", str(project)])
    assert result.returncode == 0
    payload = json.loads(result.stdout)
    assert payload["validator_version"]
    assert payload["files_checked"]
    assert "summary" in payload
    assert payload["summary"]["error"] == 0


def test_verbose_includes_ok_results(tmp_path):
    project = _make_project(tmp_path, VALID_LOCAL)
    quiet = _run([str(project)])
    verbose = _run(["--verbose", str(project)])
    # Verbose strictly contains more output lines than quiet.
    assert verbose.stdout.count("OK") > quiet.stdout.count("OK")


# ---------------------------------------------------------------------------
# Optional --check-commands
# ---------------------------------------------------------------------------


def test_check_commands_flags_missing_binary(tmp_path):
    bad_local = VALID_LOCAL.replace("build: poetry build", "build: definitely-not-a-real-binary-xyz")
    project = _make_project(tmp_path, bad_local)
    result = _run(["--check-commands", str(project)])
    assert result.returncode == 1
    assert "definitely-not-a-real-binary-xyz" in result.stdout


# ---------------------------------------------------------------------------
# YAML parser corner cases
# ---------------------------------------------------------------------------


def test_yaml_fence_extraction(tmp_path):
    fenced_local = textwrap.dedent("""\
        # Forge local config

        ```yaml
        components:
          language: python
          framework: django
          testing: pytest
        commands:
          build: ./manage.py check
          test: pytest
          lint: ruff check
        ```
        """)
    project = _make_project(tmp_path, fenced_local)
    result = _run([str(project)])
    assert result.returncode == 0, result.stdout + result.stderr


def test_inline_comments_stripped(tmp_path):
    commented = textwrap.dedent("""\
        ---
        components:
          language: python   # primary
          framework: fastapi  # 0.110+
          testing: pytest
        commands:
          build: pip install
          test: pytest
        ---
        """)
    project = _make_project(tmp_path, commented)
    result = _run([str(project)])
    assert result.returncode in (0, 2), result.stdout + result.stderr


# ---------------------------------------------------------------------------
# Module API (no subprocess)
# ---------------------------------------------------------------------------


def test_main_returns_int(tmp_path):
    project = _make_project(tmp_path, VALID_LOCAL)
    sys.path.insert(0, str(REPO))
    try:
        from shared.config_validator import main  # noqa: WPS433
    finally:
        sys.path.pop(0)
    rc = main([str(project)])
    assert rc == 0


@pytest.mark.parametrize("framework,language,expected_warning", [
    ("k8s", "python", "language: null"),
    ("go-stdlib", "rust", "language: go"),
    ("embedded", "python", "language: c or cpp"),
])
def test_framework_compat_warnings(tmp_path, framework, language, expected_warning):
    local = textwrap.dedent(f"""\
        ---
        components:
          language: {language}
          framework: {framework}
          testing: pytest
        commands:
          build: x
          test: y
        ---
        """)
    project = _make_project(tmp_path, local)
    result = _run([str(project)])
    assert expected_warning in result.stdout
