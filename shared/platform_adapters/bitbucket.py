# shared/platform_adapters/bitbucket.py
"""Bitbucket Cloud adapter — pure stdlib urllib.request against REST v2.0.

Wired up in D5 (mega-consolidation). Called by `agents/fg-710-post-run.md`
once per non-actionable verdict.

Contract: see `shared/platform_adapters/__init__.py` (`PlatformAdapter`).
- `pr_url` — full HTTPS URL to the PR (e.g.
  `https://bitbucket.org/workspace/repo/pull-requests/7`).
- `body` — markdown comment body.
- `auth` — `{"method": "app-password" | "none",
             "username": "<atlassian user>", "token": "<app password>"}`.
  Falls back to env vars `BITBUCKET_USERNAME` + `BITBUCKET_APP_PASSWORD`
  when not provided.

Never raises for expected failure modes — returns `posted=False` with an
`error` string instead.
"""
from __future__ import annotations

import base64
import json
import os
import re
import urllib.error
import urllib.request

_PR_URL_RE = re.compile(
    r"^https?://(?P<host>[^/]+)/(?P<workspace>[^/]+)/(?P<repo>[^/]+)/pull-requests/(?P<num>\d+)"
)


def _parse_pr_url(pr_url: str) -> tuple[str, str, str]:
    m = _PR_URL_RE.match(pr_url.strip())
    if not m:
        raise ValueError(f"bitbucket adapter: cannot parse PR URL: {pr_url}")
    return m.group("workspace"), m.group("repo"), m.group("num")


def _post_via_urllib(
    workspace: str, repo: str, num: str, body: str, username: str, token: str
) -> dict:
    url = (
        f"https://api.bitbucket.org/2.0/repositories/"
        f"{workspace}/{repo}/pullrequests/{num}/comments"
    )
    payload = json.dumps({"content": {"raw": body}}).encode("utf-8")
    basic = base64.b64encode(f"{username}:{token}".encode("utf-8")).decode("ascii")
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Authorization", f"Basic {basic}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw = resp.read().decode("utf-8")
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"raw": raw}


def post_comment(pr_url: str, body: str, auth: dict) -> dict:
    """Post a comment on a Bitbucket Cloud PR. Returns a `PostResult` dict."""
    try:
        workspace, repo, num = _parse_pr_url(pr_url)
    except ValueError as e:
        return {"posted": False, "response": "", "error": str(e)}

    auth = auth or {}
    username = auth.get("username") or os.environ.get("BITBUCKET_USERNAME", "")
    token = auth.get("token") or os.environ.get("BITBUCKET_APP_PASSWORD", "")

    if not username or not token:
        return {
            "posted": False,
            "response": "",
            "error": "missing BITBUCKET_USERNAME and/or BITBUCKET_APP_PASSWORD",
        }

    try:
        response = _post_via_urllib(workspace, repo, num, body, username, token)
        return {"posted": True, "response": response, "error": None}
    except urllib.error.HTTPError as e:
        return {"posted": False, "response": "", "error": f"HTTP {e.code}: {e.reason}"}
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return {"posted": False, "response": "", "error": f"network: {e}"}
