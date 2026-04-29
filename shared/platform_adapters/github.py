# shared/platform_adapters/github.py
"""GitHub adapter — posts a PR/issue comment via `gh api` CLI when present,
falling back to stdlib urllib.request against the REST v3 API.

Wired up in D5 (mega-consolidation). Called by `agents/fg-710-post-run.md`
once per non-actionable verdict.

Contract: see `shared/platform_adapters/__init__.py` (`PlatformAdapter`).
- `pr_url` — full HTTPS URL to the PR (e.g.
  `https://github.com/owner/repo/pull/123`).
- `body` — markdown comment body.
- `auth` — `{"method": "gh-cli" | "none", "token": "<optional override>"}`.
  The adapter resolves the actual token from `GITHUB_TOKEN` env var when
  `gh` is unavailable; if neither route works, `posted=False` is returned
  and fg-710 logs `FEEDBACK-POST-FAILED`.

This module never raises for expected failure modes — it returns a
`PostResult` with `posted=False, error=<reason>` instead. fg-710 maps that
to `defended_local_only` / `acknowledged_local_only`.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import urllib.error
import urllib.request

_PR_URL_RE = re.compile(
    r"^https?://(?P<host>[^/]+)/(?P<owner>[^/]+)/(?P<repo>[^/]+)/pull/(?P<num>\d+)"
)


def _parse_pr_url(pr_url: str) -> tuple[str, str, str, str]:
    m = _PR_URL_RE.match(pr_url.strip())
    if not m:
        raise ValueError(f"github adapter: cannot parse PR URL: {pr_url}")
    host = m.group("host")
    api_base = "https://api.github.com" if host == "github.com" else f"https://{host}/api/v3"
    return api_base, m.group("owner"), m.group("repo"), m.group("num")


def _post_via_gh_cli(api_base: str, owner: str, repo: str, num: str, body: str) -> dict:
    # `gh api` honours its own auth (gh-cli login) — preferred path.
    cmd = [
        "gh",
        "api",
        "--method",
        "POST",
        "-H",
        "Accept: application/vnd.github+json",
        f"/repos/{owner}/{repo}/issues/{num}/comments",
        "-f",
        f"body={body}",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if proc.returncode != 0:
        raise RuntimeError(f"gh api failed: {proc.stderr.strip() or proc.stdout.strip()}")
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"raw": proc.stdout}


def _post_via_urllib(api_base: str, owner: str, repo: str, num: str, body: str, token: str) -> dict:
    url = f"{api_base}/repos/{owner}/{repo}/issues/{num}/comments"
    payload = json.dumps({"body": body}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    """Post a top-level comment on a GitHub PR.

    Returns a dict matching `PostResult`. Never raises for auth/network
    failures — fg-710 maps `posted=False` to local-only addressed states.
    """
    try:
        api_base, owner, repo, num = _parse_pr_url(pr_url)
    except ValueError as e:
        return {"posted": False, "response": "", "error": str(e)}

    method = (auth or {}).get("method", "none")
    token = (auth or {}).get("token") or os.environ.get("GITHUB_TOKEN", "")

    # Prefer gh CLI when method is gh-cli or unspecified and gh is on PATH.
    if method in ("gh-cli", "none") and shutil.which("gh"):
        try:
            response = _post_via_gh_cli(api_base, owner, repo, num, body)
            return {"posted": True, "response": response, "error": None}
        except (subprocess.TimeoutExpired, RuntimeError, OSError) as e:
            # Fall through to urllib if a token is available.
            if not token:
                return {"posted": False, "response": "", "error": f"gh-cli failed: {e}"}

    if not token:
        return {
            "posted": False,
            "response": "",
            "error": "no GITHUB_TOKEN and gh CLI unavailable/failed",
        }

    try:
        response = _post_via_urllib(api_base, owner, repo, num, body, token)
        return {"posted": True, "response": response, "error": None}
    except urllib.error.HTTPError as e:
        return {"posted": False, "response": "", "error": f"HTTP {e.code}: {e.reason}"}
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return {"posted": False, "response": "", "error": f"network: {e}"}
