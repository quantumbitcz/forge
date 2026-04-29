# tests/unit/platform_detect_test.py
"""Tests for shared/platform-detect.py — VCS platform detection."""
from __future__ import annotations

import subprocess
from unittest.mock import patch

import pytest

from tests.unit.conftest import load_hyphenated_module


def _load_module():
    return load_hyphenated_module("shared/platform-detect.py", "platform_detect")


@pytest.fixture(scope="module")
def platform_detect():
    return _load_module()


def _git_remote(stdout: str) -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess(args=[], returncode=0, stdout=stdout)


def test_detects_github(platform_detect, tmp_path, monkeypatch):
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)
    with patch.object(platform_detect, "subprocess") as sub:
        sub.run.return_value = _git_remote("https://github.com/quantumbitcz/forge.git\n")
        sub.TimeoutExpired = subprocess.TimeoutExpired
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "github"
    assert result["api_base"] == "https://api.github.com"
    assert result["auth_method"] == "gh-cli"
    # GitHub does not need an env-var token (gh CLI handles auth) — no warning.
    assert result["warning"] is None


def test_detects_gitlab_com(platform_detect, tmp_path, monkeypatch):
    monkeypatch.setenv("GITLAB_TOKEN", "glpat-fake")
    with patch.object(platform_detect, "subprocess") as sub:
        sub.run.return_value = _git_remote("git@gitlab.com:group/project.git\n")
        sub.TimeoutExpired = subprocess.TimeoutExpired
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "gitlab"
    assert result["api_base"] == "https://gitlab.com/api/v4"


def test_detects_self_hosted_gitlab_via_explicit_override(platform_detect, tmp_path, monkeypatch):
    monkeypatch.setenv("GITLAB_TOKEN", "glpat-fake")
    config = {"platform": {"detection": "gitlab", "remote_name": "origin"}}
    with patch.object(platform_detect, "subprocess") as sub:
        sub.run.return_value = _git_remote("https://gitlab.acme.io/team/repo.git\n")
        sub.TimeoutExpired = subprocess.TimeoutExpired
        result = platform_detect.detect_platform(tmp_path, config)
    assert result["platform"] == "gitlab"
    # api_base honors the host of the explicit remote URL.
    assert result["api_base"] == "https://gitlab.acme.io/api/v4"


def test_detects_bitbucket_org(platform_detect, tmp_path, monkeypatch):
    monkeypatch.setenv("BITBUCKET_APP_PASSWORD", "secret")
    with patch.object(platform_detect, "subprocess") as sub:
        sub.run.return_value = _git_remote("https://bitbucket.org/team/repo.git\n")
        sub.TimeoutExpired = subprocess.TimeoutExpired
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "bitbucket"
    assert result["api_base"] == "https://api.bitbucket.org/2.0"


def test_detects_gitea_via_api_probe(platform_detect, tmp_path, monkeypatch):
    monkeypatch.setenv("GITEA_TOKEN", "gitea-fake")

    # The remote URL is a self-hosted host with no `gitea` substring; the probe
    # is what tells us it's Gitea/Forgejo.
    def fake_urlopen(req, timeout=None):  # noqa: ANN001
        class _Resp:
            def read(self, _n):
                return b'{"version": "1.21.0", "server": "Gitea"}'

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        return _Resp()

    with patch.object(platform_detect, "subprocess") as sub, \
         patch.object(platform_detect.urllib.request, "urlopen", side_effect=fake_urlopen):
        sub.run.return_value = _git_remote("git@code.acme.io:team/repo.git\n")
        sub.TimeoutExpired = subprocess.TimeoutExpired
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "gitea"
    assert result["api_base"] == "https://code.acme.io/api/v1"


def test_unknown_remote_returns_unknown(platform_detect, tmp_path, monkeypatch):
    # Probe fails (no Gitea signature in body).
    def fake_urlopen(req, timeout=None):  # noqa: ANN001
        class _Resp:
            def read(self, _n):
                return b"<html>nothing here</html>"

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        return _Resp()

    with patch.object(platform_detect, "subprocess") as sub, \
         patch.object(platform_detect.urllib.request, "urlopen", side_effect=fake_urlopen):
        sub.run.return_value = _git_remote("https://my-vcs.example/team/repo.git\n")
        sub.TimeoutExpired = subprocess.TimeoutExpired
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "unknown"
    assert result["auth_method"] == "none"


def test_explicit_override_skips_auto_detect(platform_detect, tmp_path, monkeypatch):
    """AC-FEEDBACK-007: explicit platform.detection wins."""
    monkeypatch.setenv("GITLAB_TOKEN", "glpat-fake")
    config = {"platform": {"detection": "gitlab"}}
    # Even though remote URL says github.com, the explicit override wins.
    with patch.object(platform_detect, "subprocess") as sub:
        sub.run.return_value = _git_remote("https://github.com/x/y.git\n")
        sub.TimeoutExpired = subprocess.TimeoutExpired
        result = platform_detect.detect_platform(tmp_path, config)
    assert result["platform"] == "gitlab"


def test_missing_auth_emits_warning_not_error(platform_detect, tmp_path, monkeypatch):
    """AC-FEEDBACK-007 + §6.1: missing auth env warns, never aborts."""
    monkeypatch.delenv("GITLAB_TOKEN", raising=False)
    with patch.object(platform_detect, "subprocess") as sub:
        sub.run.return_value = _git_remote("https://gitlab.com/team/repo.git\n")
        sub.TimeoutExpired = subprocess.TimeoutExpired
        result = platform_detect.detect_platform(tmp_path)
    assert result["platform"] == "gitlab"
    assert result["warning"] is not None
    assert "GITLAB_TOKEN" in result["warning"]


def test_invalid_explicit_detection_raises(platform_detect, tmp_path):
    """Detection enum is validated."""
    config = {"platform": {"detection": "perforce"}}
    with pytest.raises(ValueError, match="platform.detection"):
        platform_detect.detect_platform(tmp_path, config)


def test_adapter_modules_importable():
    """Each per-platform adapter module exists with a post_comment function."""
    import importlib

    for name in ("github", "gitlab", "bitbucket", "gitea"):
        mod = importlib.import_module(f"shared.platform_adapters.{name}")
        assert hasattr(mod, "post_comment"), f"{name} adapter missing post_comment"


# --- CLI surface tests (CRITICAL-2: orchestrator invocation) ---

import json  # noqa: E402
import sys  # noqa: E402
from pathlib import Path  # noqa: E402

_REPO_ROOT = Path(__file__).resolve().parents[2]
_SCRIPT = _REPO_ROOT / "shared" / "platform-detect.py"


def test_cli_emits_json_envelope(tmp_path):
    """`python3 shared/platform-detect.py --repo-root <path>` returns JSON."""
    proc = subprocess.run(
        [sys.executable, str(_SCRIPT), "--repo-root", str(tmp_path)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    # CLI never errors — non-detection is encoded as platform="unknown".
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    expected_keys = {
        "platform",
        "remote_url",
        "api_base",
        "auth_method",
        "detected_at",
        "warning",
    }
    assert set(data.keys()) == expected_keys


def test_cli_honors_explicit_detection_none(tmp_path):
    """`--config-platform-detection none` short-circuits to unknown."""
    proc = subprocess.run(
        [
            sys.executable,
            str(_SCRIPT),
            "--repo-root",
            str(tmp_path),
            "--config-platform-detection",
            "none",
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, proc.stderr
    data = json.loads(proc.stdout)
    assert data["platform"] == "unknown"
    assert data["auth_method"] == "none"


def test_cli_invalid_choice_rejected(tmp_path):
    """argparse rejects unsupported detection values (exit 2)."""
    proc = subprocess.run(
        [
            sys.executable,
            str(_SCRIPT),
            "--repo-root",
            str(tmp_path),
            "--config-platform-detection",
            "perforce",
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert proc.returncode != 0
    assert "perforce" in proc.stderr or "invalid choice" in proc.stderr.lower()
