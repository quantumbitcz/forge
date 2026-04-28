# shared/platform-detect.py
"""VCS platform detection.

Reads `git remote get-url <remote_name>` and matches against known host
patterns. Falls back to a Gitea API probe (best-effort; the timeout is
per-socket-operation after connect — see _gitea_probe). Honors explicit
override via config['platform']['detection'].

Spec: docs/superpowers/specs/2026-04-27-skill-consolidation-design.md §6.1
ACs:  AC-FEEDBACK-006, AC-FEEDBACK-007.
"""
from __future__ import annotations

import datetime
import os
import re
import subprocess
import urllib.error
import urllib.request
from pathlib import Path
from typing import TypedDict
from urllib.parse import urlparse


class PlatformInfo(TypedDict):
    platform: str  # github | gitlab | bitbucket | gitea | unknown
    remote_url: str
    api_base: str
    auth_method: str
    detected_at: str
    warning: str | None


_KNOWN_HOSTS: tuple[tuple[re.Pattern[str], str, str, str], ...] = (
    (re.compile(r"(?:^|@|//)github\.com[:/]"), "github", "https://api.github.com", "gh-cli"),
    (re.compile(r"(?:^|@|//)gitlab\.com[:/]"), "gitlab", "https://gitlab.com/api/v4", "glab-cli"),
    (
        re.compile(r"(?:^|@|//)bitbucket\.org[:/]"),
        "bitbucket",
        "https://api.bitbucket.org/2.0",
        "app-password",
    ),
)

_GITEA_PROBE_TIMEOUT_SECONDS = 3
_VALID_DETECTION_VALUES = ("auto", "github", "gitlab", "bitbucket", "gitea")


def _now_iso() -> str:
    return datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _read_remote_url(repo_root: Path, remote_name: str) -> str | None:
    try:
        proc = subprocess.run(
            ["git", "remote", "get-url", remote_name],
            cwd=repo_root,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def _host_from_url(url: str) -> str | None:
    # Handle scp-style git@host:path/repo.git as well as URL form.
    if "://" in url:
        parsed = urlparse(url)
        return parsed.hostname
    if "@" in url and ":" in url:
        return url.split("@", 1)[1].split(":", 1)[0]
    return None


def _gitea_probe(host: str) -> bool:
    """Probe <host>/api/v1/version. True iff Gitea/Forgejo.

    Note: the timeout (_GITEA_PROBE_TIMEOUT_SECONDS) applies per-socket-operation
    AFTER connect, not as a wall-clock cap. DNS resolution and TLS handshake are
    not bounded by it. Worst-case probe duration is unbounded; use a separate
    wall-clock budget at the orchestrator level if strict bounding is needed.
    """
    if not host:
        return False
    url = f"https://{host}/api/v1/version"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "forge-platform-probe/1.0"})
        with urllib.request.urlopen(req, timeout=_GITEA_PROBE_TIMEOUT_SECONDS) as resp:
            body = resp.read(2048).decode("utf-8", errors="ignore").lower()
    except (urllib.error.URLError, TimeoutError, OSError):
        return False
    return "gitea" in body or "forgejo" in body


def _api_base_for(platform: str, remote_url: str) -> str:
    """Compute API base URL for a detected platform."""
    if platform == "github":
        return "https://api.github.com"
    if platform == "gitlab":
        host = _host_from_url(remote_url) or "gitlab.com"
        return f"https://{host}/api/v4"
    if platform == "bitbucket":
        return "https://api.bitbucket.org/2.0"
    if platform == "gitea":
        host = _host_from_url(remote_url)
        return f"https://{host}/api/v1" if host else ""
    return ""


def _auth_method_for(platform: str) -> str:
    return {
        "github": "gh-cli",
        "gitlab": "glab-cli",
        "bitbucket": "app-password",
        "gitea": "gitea-token",
        "unknown": "none",
    }.get(platform, "none")


def _auth_env_for(platform: str) -> str | None:
    # GitHub intentionally absent: gh CLI handles auth, not env vars.
    return {
        "gitlab": "GITLAB_TOKEN",
        "bitbucket": "BITBUCKET_APP_PASSWORD",
        "gitea": "GITEA_TOKEN",
    }.get(platform)


def detect_platform(repo_root: Path, config: dict | None = None) -> PlatformInfo:
    """Detect the VCS platform for the repo at repo_root.

    Resolution:
      1. config['platform']['detection'] explicit override (skip auto path).
      2. git remote get-url <remote_name> match against known hosts.
      3. Gitea API probe as last resort.
      4. Fallback: platform = "unknown".
    """
    if config is None:
        config = {}
    platform_cfg = (config.get("platform") or {})
    detection = platform_cfg.get("detection", "auto")
    remote_name = platform_cfg.get("remote_name", "origin")

    if detection not in _VALID_DETECTION_VALUES:
        raise ValueError(
            f"platform.detection must be one of {_VALID_DETECTION_VALUES}; got {detection!r}"
        )

    remote_url = _read_remote_url(repo_root, remote_name) or ""

    if detection != "auto":
        platform = detection
    else:
        platform = "unknown"
        for pattern, name, _api_base, _auth in _KNOWN_HOSTS:
            if pattern.search(remote_url):
                platform = name
                break
        if platform == "unknown" and remote_url:
            host = _host_from_url(remote_url)
            if host and _gitea_probe(host):
                platform = "gitea"

    api_base = _api_base_for(platform, remote_url)
    auth_method = _auth_method_for(platform)

    warning: str | None = None
    env_var = _auth_env_for(platform)
    if env_var and not os.environ.get(env_var):
        # GitHub uses gh CLI auth (no env var in _auth_env_for); for others the env
        # var is the canonical auth — warn (not abort) per §6.1.
        warning = (
            f"platform={platform} but {env_var} is not set; defenses will be logged "
            f"locally with addressed: defended_local_only"
        )

    return {
        "platform": platform,
        "remote_url": remote_url,
        "api_base": api_base,
        "auth_method": auth_method,
        "detected_at": _now_iso(),
        "warning": warning,
    }
